package main

import (
	"context"
	"encoding/json"
	"net/http"
)

const removeMFAFactorRoute = publicAuthPrefix + "/festapp/mfa/factors/remove"

func (store *channelStore) removeMFAFactor(w http.ResponseWriter, r *http.Request, origin string) {
	setRegistrationHeaders(w, origin)
	var input struct {
		FactorID       string `json:"factorId"`
		ConfirmDisable bool   `json:"confirmDisable"`
	}
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if !uuidText.MatchString(input.FactorID) {
		authError(w, http.StatusBadRequest, "invalid_mfa_factor")
		return
	}
	actor := store.registrationActor(w, r, nil, false)
	if actor == nil {
		return
	}
	store.removeCredential(w, r, "begin_account_mfa_factor_removal_v1", "/factors/"+input.FactorID, map[string]any{
		"p_user": actor.UserID, "p_session": actor.SessionID,
		"p_factor": input.FactorID, "p_confirm_disable": input.ConfirmDisable,
	})
}

func (store *channelStore) removeCredential(w http.ResponseWriter, r *http.Request, begin, providerPath string, args map[string]any) {
	var operation struct {
		State          string `json:"state"`
		ID             string `json:"id"`
		LastFactor     bool   `json:"lastFactor"`
		RevokesSession bool   `json:"revokesSession"`
	}
	if err := store.rpc(r.Context(), begin, store.token, args, &operation); err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_change_unavailable")
		return
	}
	switch operation.State {
	case "confirm_disable":
		authError(w, http.StatusConflict, "confirm_disable_mfa")
		return
	case "password_required":
		authError(w, http.StatusConflict, "password_proof_required")
		return
	case "busy":
		authError(w, http.StatusConflict, "factor_change_pending")
		return
	case "reserved":
		if uuidText.MatchString(operation.ID) {
			break
		}
		fallthrough
	default:
		authError(w, http.StatusForbidden, "mfa_operation_refused")
		return
	}

	// A client disconnect cannot leave a successful provider mutation without
	// revocation. Each upstream call remains bounded by the HTTP client timeout.
	request := r.WithContext(context.WithoutCancel(r.Context()))
	status, _ := store.providerRequest(request, http.MethodDelete, providerPath, nil)
	var completed bool
	procedure := "finish_account_mfa_factor_removal_v1"
	if status >= 400 && status < 500 {
		procedure = "cancel_account_mfa_factor_removal_v1"
	}
	if status != 0 && status < 500 {
		_ = store.rpc(request.Context(), procedure, store.token, map[string]string{"p_operation": operation.ID}, &completed)
	}
	if !completed {
		authError(w, http.StatusServiceUnavailable, "factor_change_pending")
		return
	}
	if procedure == "cancel_account_mfa_factor_removal_v1" {
		authError(w, http.StatusForbidden, "mfa_operation_refused")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"removed": true, "disabledMfa": operation.LastFactor, "revokesSession": operation.RevokesSession})
}
