package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"regexp"
)

const enrollTOTPRouter = publicAuthPrefix + "/festapp/mfa/totp/enroll"
const verifyTOTPRouter = publicAuthPrefix + "/festapp/mfa/totp/verify"

// GoTrue returns the enrollment QR as an inline SVG. Its response can be
// larger than the maximum accepted Auth request.
const maxAuthProviderResponse = 4 * 1024 * 1024

var uuidText = regexp.MustCompile(`^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$`)
var totpCode = regexp.MustCompile(`^[0-9]{6}$`)

type totpRequest struct {
	Recovery     bool   `json:"recovery"`
	Receipt      string `json:"receipt"`
	FriendlyName string `json:"friendlyName"`
	FactorID     string `json:"factorId"`
	Code         string `json:"code"`
}

func (store *channelStore) advanceFactorRegistration(r *http.Request, actor *registrationActor, receipt, origin, method, operation, factor string) (bool, error) {
	args := map[string]any{
		"p_receipt": receipt, "p_user": actor.UserID, "p_session": actor.SessionID,
		"p_origin": origin, "p_method": method, "p_operation": operation, "p_recovery": actor.Recovery,
	}
	if factor != "" {
		args["p_factor"] = factor
	}
	var allowed bool
	err := store.rpc(r.Context(), "advance_mfa_factor_registration_v1", store.token, args, &allowed)
	return allowed, err
}

func (store *channelStore) providerPOST(r *http.Request, path string, body any) (status int, response []byte) {
	return store.providerRequest(r, http.MethodPost, path, body)
}

func (store *channelStore) providerRequest(r *http.Request, method, path string, body any) (status int, response []byte) {
	payload, err := json.Marshal(body)
	if err != nil {
		return 0, nil
	}
	var reader io.Reader = bytes.NewReader(payload)
	if body == nil && method != http.MethodPost {
		reader = nil
	}
	request, err := http.NewRequestWithContext(r.Context(), method, store.providerAuth+path, reader)
	if err != nil {
		return 0, nil
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", r.Header.Get("Authorization"))
	request.Header.Set("apikey", store.token)
	if address := r.Header.Get("X-Festapp-Client-IP"); address != "" {
		request.Header.Set("X-Festapp-Client-IP", address)
	}
	result, err := store.client.Do(request)
	if err != nil {
		return 0, nil
	}
	defer result.Body.Close()
	response, err = io.ReadAll(io.LimitReader(result.Body, maxAuthProviderResponse+1))
	if err != nil || len(response) > maxAuthProviderResponse ||
		(result.StatusCode != http.StatusNoContent && !json.Valid(response)) {
		log.Printf("Auth provider response rejected (status=%d bytes=%d encoding=%q readError=%v)",
			result.StatusCode, len(response), result.Header.Get("Content-Encoding"), err)
		return 0, nil
	}
	return result.StatusCode, response
}

func (store *channelStore) totpRegistration(w http.ResponseWriter, r *http.Request, origin string) {
	var input totpRequest
	if !readRegistrationBody(w, r, &input) {
		return
	}
	verify := r.URL.Path == verifyTOTPRouter
	if !uuidText.MatchString(input.Receipt) || len(input.FriendlyName) > 128 ||
		(verify && (!uuidText.MatchString(input.FactorID) || !totpCode.MatchString(input.Code))) {
		authError(w, http.StatusBadRequest, "invalid_totp_registration")
		return
	}
	actor := store.registrationActor(w, r, nil, input.Recovery)
	if actor == nil {
		return
	}
	operation := "enroll"
	if verify {
		operation = "verify"
	}
	allowed, err := store.advanceFactorRegistration(r, actor, input.Receipt, origin, "totp", operation, input.FactorID)
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
	if verify {
		status, body = store.verifyTOTP(r, actor, input, origin)
	} else {
		status, body = store.enrollTOTP(r, actor, input, origin)
	}
	if status == 0 {
		authError(w, http.StatusBadGateway, "totp_registration_unavailable")
		return
	}
	setRegistrationHeaders(w, origin)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func (store *channelStore) enrollTOTP(r *http.Request, actor *registrationActor, input totpRequest, origin string) (int, []byte) {
	status, body := store.providerPOST(r, "/factors", map[string]string{
		"factor_type": "totp", "friendly_name": enrollmentFactorName(input.FriendlyName),
	})
	if status < 200 || status >= 300 {
		return status, body
	}
	var result struct {
		ID   string `json:"id"`
		TOTP struct {
			Secret string `json:"secret"`
			URI    string `json:"uri"`
		} `json:"totp"`
	}
	if json.Unmarshal(body, &result) != nil || !uuidText.MatchString(result.ID) ||
		result.TOTP.Secret == "" || result.TOTP.URI == "" {
		log.Print("TOTP enrollment returned an invalid provider receipt")
		return 0, nil
	}
	bound, err := store.advanceFactorRegistration(r, actor, input.Receipt, origin, "totp", "bind", result.ID)
	if err != nil || !bound {
		log.Printf("TOTP enrollment could not bind its provider receipt (bound=%t, error=%v)", bound, err)
		return 0, nil
	}
	// Let the client render the QR from the provisioning URI and offer the
	// manual key. The large inline SVG from GoTrue is not needed.
	reply, err := json.Marshal(result)
	if err != nil {
		return 0, nil
	}
	return status, reply
}

func (store *channelStore) verifyTOTP(r *http.Request, actor *registrationActor, input totpRequest, origin string) (int, []byte) {
	factor := "/factors/" + input.FactorID
	status, body := store.providerPOST(r, factor+"/challenge", nil)
	if status == 0 || status >= 500 {
		return 0, nil
	}
	if status < 200 || status >= 300 {
		_, _ = store.advanceFactorRegistration(r, actor, input.Receipt, origin, "totp", "retry", input.FactorID)
		return status, body
	}
	var challenge struct {
		ID string `json:"id"`
	}
	if json.Unmarshal(body, &challenge) != nil || !uuidText.MatchString(challenge.ID) {
		return 0, nil
	}
	status, body = store.providerPOST(r, factor+"/verify", map[string]string{
		"challenge_id": challenge.ID, "code": input.Code,
	})
	if status == 0 || status >= 500 {
		// The provider may have completed the mutation. Do not reopen the
		// reservation automatically after an uncertain result.
		return 0, nil
	}
	transition := "finish"
	if status < 200 || status >= 300 {
		transition = "retry"
	}
	saved, err := store.advanceFactorRegistration(r, actor, input.Receipt, origin, "totp", transition, input.FactorID)
	if err != nil || !saved {
		return 0, nil
	}
	return status, body
}
