package main

import (
	"net/http"
	"strings"
)

func bearerToken(header string) (string, bool) {
	token, ok := strings.CutPrefix(header, "Bearer ")
	return token, ok && token != "" && len(token) <= 8192 && !strings.ContainsAny(token, " \r\n")
}

func (store *channelStore) allowAuthOperation(w http.ResponseWriter, r *http.Request, name string, params map[string]string) bool {
	bearer, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		authError(w, http.StatusUnauthorized, "invalid_session")
		return false
	}
	var allowed bool
	if err := store.rpc(r.Context(), name, bearer, params, &allowed); err != nil || !allowed {
		authError(w, http.StatusForbidden, "mfa_operation_refused")
		return false
	}
	return true
}

func (store *channelStore) protectPublicAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		subpath := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, publicAuthPrefix), "/")
		parts := strings.Split(subpath, "/")
		switch {
		case r.Method == http.MethodOptions:
			// The pinned Auth service owns ordinary cross-origin preflights.
		case subpath == "/factors" || strings.HasPrefix(subpath, "/factors/"):
			if len(parts) != 4 || r.Method != http.MethodPost || !uuidText.MatchString(parts[2]) ||
				(parts[3] != "challenge" && parts[3] != "verify") {
				authError(w, http.StatusForbidden, "mfa_management_route_required")
				return
			}
			if !store.allowAuthOperation(w, r, "can_use_existing_mfa_factor_v1", map[string]string{"p_factor": parts[2]}) {
				return
			}
		case subpath == "/passkeys" || strings.HasPrefix(subpath, "/passkeys/"):
			authError(w, http.StatusForbidden, "passkey_channel_required")
			return
		case subpath == "/admin" || strings.HasPrefix(subpath, "/admin/") || subpath == "/invite":
			authError(w, http.StatusForbidden, "internal_auth_route_required")
			return
		case subpath == "/user/identities" || strings.HasPrefix(subpath, "/user/identities/"):
			authError(w, http.StatusForbidden, "account_management_route_required")
			return
		case subpath == "/user" && r.Method == http.MethodPut:
			if !store.allowAuthOperation(w, r, "can_update_public_auth_account_v1", map[string]string{}) {
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
