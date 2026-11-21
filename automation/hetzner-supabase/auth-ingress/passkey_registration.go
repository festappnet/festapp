package main

import (
	"encoding/json"
	"net/http"
)

const optionsPasskeyRegistrationRoute = publicAuthPrefix + "/festapp/passkey/registration/options"
const verifyPasskeyRegistrationRoute = publicAuthPrefix + "/festapp/passkey/registration/verify"

type passkeyRegistrationRequest struct {
	Receipt     string          `json:"receipt"`
	ChallengeID string          `json:"challengeId"`
	Credential  json.RawMessage `json:"credential"`
}

func (store *channelStore) passkeyRegistration(w http.ResponseWriter, r *http.Request, origin string) {
	setRegistrationHeaders(w, origin)
	var input passkeyRegistrationRequest
	if !readRegistrationBody(w, r, &input) {
		return
	}
	verify := r.URL.Path == verifyPasskeyRegistrationRoute
	if !uuidText.MatchString(input.Receipt) || (verify && !uuidText.MatchString(input.ChallengeID)) {
		authError(w, http.StatusBadRequest, "invalid_passkey_registration")
		return
	}
	if verify && !requireWebAuthnCredential(w, input.Credential, true, origin) {
		return
	}
	actor := store.registrationActor(w, r, nil, false)
	if actor == nil {
		return
	}

	advance := func(operation, challenge, credential string) (bool, error) {
		args := map[string]string{
			"p_receipt": input.Receipt, "p_user": actor.UserID, "p_session": actor.SessionID,
			"p_origin": origin, "p_operation": operation,
		}
		if challenge != "" {
			args["p_challenge"] = challenge
		}
		if credential != "" {
			args["p_credential"] = credential
		}
		var allowed bool
		err := store.rpc(r.Context(), "advance_passkey_registration_v1", store.token, args, &allowed)
		return allowed, err
	}
	operation := "options"
	var payload any = map[string]string{}
	if verify {
		operation = "verify"
		payload = map[string]any{"challenge_id": input.ChallengeID, "credential": input.Credential}
	}
	allowed, err := advance(operation, input.ChallengeID, "")
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if !allowed {
		authError(w, http.StatusForbidden, "registration_unavailable")
		return
	}

	status, body := store.providerPOST(r, "/passkeys/registration/"+operation, payload)
	if status == 0 || status >= 500 {
		authError(w, http.StatusBadGateway, "passkey_registration_unavailable")
		return
	}
	if status >= 200 && status < 300 {
		var result struct {
			ID          string `json:"id"`
			ChallengeID string `json:"challenge_id"`
		}
		if json.Unmarshal(body, &result) != nil {
			authError(w, http.StatusBadGateway, "passkey_registration_unavailable")
			return
		}
		var saved bool
		if verify && uuidText.MatchString(result.ID) {
			saved, err = advance("finish", input.ChallengeID, result.ID)
		} else if !verify && uuidText.MatchString(result.ChallengeID) {
			saved, err = advance("bind", result.ChallengeID, "")
		}
		if err != nil || !saved {
			authError(w, http.StatusBadGateway, "passkey_registration_unavailable")
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
