package main

import (
	"net/http"
	"strings"
)

const listPasskeysRoute = publicAuthPrefix + "/festapp/passkey/manage/list"
const renamePasskeyRoute = publicAuthPrefix + "/festapp/passkey/manage/rename"
const removePasskeyRoute = publicAuthPrefix + "/festapp/passkey/manage/remove"

func (store *channelStore) managePasskeys(w http.ResponseWriter, r *http.Request, origin string) {
	setRegistrationHeaders(w, origin)
	var input struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if r.URL.Path == listPasskeysRoute {
		bearer, ok := bearerToken(r.Header.Get("Authorization"))
		var decision string
		if !ok || store.rpc(r.Context(), "get_account_assurance_v1", bearer, map[string]string{}, &decision) != nil ||
			decision != "allowed" {
			authError(w, http.StatusForbidden, "mfa_operation_refused")
			return
		}
		store.passkeyProviderResponse(w, r, http.MethodGet, "/passkeys", nil)
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	if !uuidText.MatchString(input.ID) || (r.URL.Path == renamePasskeyRoute &&
		(input.Name == "" || len(input.Name) > 120)) {
		authError(w, http.StatusBadRequest, "invalid_passkey_management")
		return
	}
	actor := store.registrationActor(w, r, nil, false)
	if actor == nil {
		return
	}
	path := "/passkeys/" + input.ID
	if r.URL.Path == renamePasskeyRoute {
		store.passkeyProviderResponse(w, r, http.MethodPatch, path, map[string]string{"friendly_name": input.Name})
		return
	}
	store.removeCredential(w, r, "begin_account_passkey_removal_v1", path, map[string]any{
		"p_user": actor.UserID, "p_session": actor.SessionID, "p_credential": input.ID,
		"p_password_proven": actor.PasswordProven,
	})
}

func (store *channelStore) passkeyProviderResponse(w http.ResponseWriter, r *http.Request, method, path string, body any) {
	status, data := store.providerRequest(r, method, path, body)
	if status == 0 || status >= 500 {
		authError(w, http.StatusBadGateway, "passkey_management_unavailable")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(data)
}
