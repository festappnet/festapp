package main

import (
	"encoding/json"
	"net/http"
)

const enrollWebAuthnRoute = publicAuthPrefix + "/festapp/mfa/webauthn/enroll"
const challengeWebAuthnRoute = publicAuthPrefix + "/festapp/mfa/webauthn/challenge"
const verifyWebAuthnRoute = publicAuthPrefix + "/festapp/mfa/webauthn/verify"

type webAuthnRegistrationRequest struct {
	Recovery     bool            `json:"recovery"`
	Receipt      string          `json:"receipt"`
	FriendlyName string          `json:"friendlyName"`
	FactorID     string          `json:"factorId"`
	ChallengeID  string          `json:"challengeId"`
	Credential   json.RawMessage `json:"credential"`
}

func requireWebAuthnCredential(w http.ResponseWriter, credential json.RawMessage, registration bool, origin string) bool {
	verified, err := hasUserVerification(credential, registration, origin)
	if err == errCredentialOrigin {
		authError(w, http.StatusForbidden, "invalid_webauthn_origin")
		return false
	}
	if err != nil {
		authError(w, http.StatusBadRequest, "invalid_webauthn_credential")
		return false
	}
	if !verified {
		authError(w, http.StatusForbidden, "webauthn_user_verification_required")
		return false
	}
	return true
}

func (store *channelStore) webAuthnRegistration(w http.ResponseWriter, r *http.Request, origin string) {
	setRegistrationHeaders(w, origin)
	var input webAuthnRegistrationRequest
	if !readRegistrationBody(w, r, &input) {
		return
	}
	enroll := r.URL.Path == enrollWebAuthnRoute
	verify := r.URL.Path == verifyWebAuthnRoute
	if !uuidText.MatchString(input.Receipt) || len(input.FriendlyName) > 128 ||
		(!enroll && !uuidText.MatchString(input.FactorID)) ||
		(verify && !uuidText.MatchString(input.ChallengeID)) {
		authError(w, http.StatusBadRequest, "invalid_webauthn_registration")
		return
	}
	if verify && !requireWebAuthnCredential(w, input.Credential, true, origin) {
		return
	}
	actor := store.registrationActor(w, r, nil, input.Recovery)
	if actor == nil {
		return
	}
	operation := "challenge"
	if enroll {
		operation = "enroll"
	} else if verify {
		operation = "verify"
	}
	advance := func(operation, factor string) (bool, error) {
		return store.advanceFactorRegistration(r, actor, input.Receipt, origin, "webauthn", operation, factor)
	}
	allowed, err := advance(operation, input.FactorID)
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if !allowed {
		authError(w, http.StatusForbidden, "registration_unavailable")
		return
	}

	var status int
	var body []byte
	factor := "/factors/" + input.FactorID
	switch operation {
	case "enroll":
		status, body = store.providerPOST(r, "/factors", map[string]string{
			"factor_type": "webauthn", "friendly_name": enrollmentFactorName(input.FriendlyName),
		})
		if status >= 200 && status < 300 {
			var result struct {
				ID string `json:"id"`
			}
			if json.Unmarshal(body, &result) != nil || !uuidText.MatchString(result.ID) {
				status = 0
				break
			}
			if bound, err := advance("bind", result.ID); err != nil || !bound {
				status = 0
			}
		}
	case "challenge":
		status, body = store.providerPOST(r, factor+"/challenge", nil)
	case "verify":
		status, body = store.providerPOST(r, factor+"/verify", map[string]any{
			"challenge_id": input.ChallengeID,
			"webauthn":     map[string]any{"type": "create", "credential_response": input.Credential},
		})
		// The provider can commit even if the HTTP response is lost. Leave
		// the reservation closed until the live factor state is reloaded.
		if status > 0 && status < 500 {
			transition := "finish"
			if status < 200 || status >= 300 {
				transition = "retry"
			}
			if saved, err := advance(transition, input.FactorID); err != nil || !saved {
				status = 0
			}
		}
	}
	if status == 0 || status >= 500 {
		authError(w, http.StatusBadGateway, "webauthn_registration_unavailable")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
