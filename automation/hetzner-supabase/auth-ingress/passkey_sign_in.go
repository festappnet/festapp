package main

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/url"
)

const optionsPasskeySignInRoute = publicAuthPrefix + "/festapp/passkey/sign-in/options"
const verifyPasskeySignInRoute = publicAuthPrefix + "/festapp/passkey/sign-in/verify"
const exchangePasskeySignInRoute = publicAuthPrefix + "/festapp/passkey/sign-in/exchange"

type passkeySignInOptions struct {
	ClientID      string `json:"clientId"`
	Organization  int64  `json:"organization"`
	RedirectURI   string `json:"redirectUri"`
	CodeChallenge string `json:"codeChallenge"`
	CaptchaToken  string `json:"captchaToken"`
}

type passkeySession struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type passkeyIdentity struct {
	UserID      string `json:"userId"`
	SessionID   string `json:"sessionId"`
	RequiresMFA bool   `json:"requiresMfa"`
}

func newPasskeySeal(key string) (cipher.AEAD, error) {
	raw, err := hex.DecodeString(key)
	if err != nil {
		return nil, err
	}
	if len(raw) != 32 {
		return nil, aes.KeySizeError(len(raw))
	}
	block, err := aes.NewCipher(raw)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCMWithRandomNonce(block)
}

func (store *channelStore) passkeySignIn(w http.ResponseWriter, r *http.Request, origin string) {
	setRegistrationHeaders(w, origin)
	if store.passkeySeal == nil {
		authError(w, http.StatusServiceUnavailable, "passkey_sign_in_unavailable")
		return
	}
	if r.Header.Get("Authorization") != "" {
		authError(w, http.StatusConflict, "passkey_sign_in_requires_anonymous_flow")
		return
	}
	switch r.URL.Path {
	case optionsPasskeySignInRoute:
		store.startPasskeySignIn(w, r, origin)
	case verifyPasskeySignInRoute:
		store.verifyPasskeySignIn(w, r, origin)
	case exchangePasskeySignInRoute:
		store.exchangePasskeySignIn(w, r, origin)
	}
}

func (store *channelStore) startPasskeySignIn(w http.ResponseWriter, r *http.Request, origin string) {
	var input passkeySignInOptions
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if input.Organization <= 0 || len(input.ClientID) == 0 || len(input.ClientID) > 128 ||
		len(input.RedirectURI) > 2048 || !opaqueCode.MatchString(input.CodeChallenge) {
		authError(w, http.StatusBadRequest, "invalid_passkey_sign_in")
		return
	}
	policy, err := store.resolveChannel(r, input.ClientID, input.Organization, origin, input.RedirectURI)
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if policy == nil || !policy.Methods["passkey"].SignIn {
		authError(w, http.StatusForbidden, "passkey_sign_in_unavailable")
		return
	}

	payload := map[string]any{}
	if input.CaptchaToken != "" {
		payload["gotrue_meta_security"] = map[string]string{"captcha_token": input.CaptchaToken}
	}
	status, body := store.providerPOST(r, "/passkeys/authentication/options", payload)
	if status == 0 || status >= 500 {
		authError(w, http.StatusBadGateway, "passkey_sign_in_unavailable")
		return
	}
	if status >= 200 && status < 300 {
		var provider struct {
			ChallengeID string `json:"challenge_id"`
		}
		if json.Unmarshal(body, &provider) != nil || !uuidText.MatchString(provider.ChallengeID) {
			authError(w, http.StatusBadGateway, "passkey_sign_in_unavailable")
			return
		}
		var issued bool
		err := store.rpc(r.Context(), "issue_passkey_sign_in_v1", store.token, map[string]any{
			"p_id": provider.ChallengeID, "p_client_id": input.ClientID, "p_organization": input.Organization,
			"p_origin": origin, "p_redirect_uri": input.RedirectURI, "p_revision": policy.Methods["passkey"].SignInRevision,
			"p_code_challenge": input.CodeChallenge,
		}, &issued)
		if err != nil || !issued {
			authError(w, http.StatusForbidden, "passkey_sign_in_unavailable")
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func (store *channelStore) verifiedPasskeyIdentity(r *http.Request, organization int64, accessToken string) *passkeyIdentity {
	var actor *passkeyIdentity
	err := store.rpc(r.Context(), "get_passkey_sign_in_actor_v1", accessToken,
		map[string]int64{"p_organization": organization}, &actor)
	if err != nil || actor == nil || !uuidText.MatchString(actor.UserID) || !uuidText.MatchString(actor.SessionID) {
		return nil
	}
	return actor
}

func (store *channelStore) revokeUndeliveredPasskeySession(r *http.Request, token string) {
	if token == "" {
		return
	}
	request := r.Clone(context.WithoutCancel(r.Context()))
	request.Header.Set("Authorization", "Bearer "+token)
	store.providerPOST(request, "/logout?scope=local", nil)
}

func (store *channelStore) verifyPasskeySignIn(w http.ResponseWriter, r *http.Request, origin string) {
	var input struct {
		ChallengeID string          `json:"challengeId"`
		Credential  json.RawMessage `json:"credential"`
	}
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if !uuidText.MatchString(input.ChallengeID) {
		authError(w, http.StatusBadRequest, "invalid_passkey_sign_in")
		return
	}
	if !requireWebAuthnCredential(w, input.Credential, false, origin) {
		return
	}
	var scope *struct {
		Organization int64  `json:"organization"`
		RedirectURI  string `json:"redirectUri"`
	}
	if err := store.rpc(r.Context(), "reserve_passkey_sign_in_v1", store.token,
		map[string]string{"p_id": input.ChallengeID, "p_origin": origin}, &scope); err != nil || scope == nil {
		authError(w, http.StatusForbidden, "passkey_sign_in_unavailable")
		return
	}
	destination, err := url.Parse(scope.RedirectURI)
	if err != nil || destination.Scheme != "https" || destination.Hostname() == "" ||
		destination.User != nil || destination.Fragment != "" || destination.RawQuery != "" {
		authError(w, http.StatusForbidden, "passkey_sign_in_unavailable")
		return
	}

	status, body := store.providerPOST(r, "/passkeys/authentication/verify",
		map[string]any{"challenge_id": input.ChallengeID, "credential": input.Credential})
	var session passkeySession
	if status != http.StatusOK || json.Unmarshal(body, &session) != nil ||
		session.AccessToken == "" || session.RefreshToken == "" {
		authError(w, http.StatusForbidden, "passkey_verification_failed")
		return
	}
	delivered := false
	defer func() {
		if !delivered {
			store.revokeUndeliveredPasskeySession(r, session.AccessToken)
		}
	}()
	actor := store.verifiedPasskeyIdentity(r, scope.Organization, session.AccessToken)
	if actor == nil {
		authError(w, http.StatusForbidden, "passkey_verification_failed")
		return
	}

	var secret [32]byte
	rand.Read(secret[:])
	code := base64.RawURLEncoding.EncodeToString(secret[:])
	digest := sha256.Sum256([]byte(code))
	plaintext, err := json.Marshal(session)
	if err != nil {
		authError(w, http.StatusBadGateway, "passkey_sign_in_unavailable")
		return
	}
	sealed := base64.RawURLEncoding.EncodeToString(store.passkeySeal.Seal(nil, nil, plaintext, digest[:]))
	var saved bool
	err = store.rpc(r.Context(), "complete_passkey_sign_in_v1", store.token, map[string]string{
		"p_id": input.ChallengeID, "p_origin": origin, "p_user": actor.UserID, "p_session": actor.SessionID,
		"p_code_hash": hex.EncodeToString(digest[:]), "p_sealed_session": sealed,
	}, &saved)
	if err != nil || !saved {
		authError(w, http.StatusForbidden, "passkey_sign_in_unavailable")
		return
	}
	delivered = true
	destination.RawQuery = url.Values{"passkey_code": {code}}.Encode()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"callback": destination.String()})
}

func (store *channelStore) exchangePasskeySignIn(w http.ResponseWriter, r *http.Request, origin string) {
	var input struct {
		ClientID     string `json:"clientId"`
		Organization int64  `json:"organization"`
		Code         string `json:"code"`
		CodeVerifier string `json:"codeVerifier"`
	}
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if input.Organization <= 0 || len(input.ClientID) == 0 || len(input.ClientID) > 128 ||
		!opaqueCode.MatchString(input.Code) || !pkceVerifier.MatchString(input.CodeVerifier) {
		authError(w, http.StatusBadRequest, "invalid_passkey_handoff")
		return
	}
	digest := sha256.Sum256([]byte(input.Code))
	challenge := sha256.Sum256([]byte(input.CodeVerifier))
	var sealed *string
	if err := store.rpc(r.Context(), "exchange_passkey_sign_in_v1", store.token, map[string]any{
		"p_client_id": input.ClientID, "p_organization": input.Organization, "p_origin": origin,
		"p_code_hash": hex.EncodeToString(digest[:]), "p_code_challenge": base64.RawURLEncoding.EncodeToString(challenge[:]),
	}, &sealed); err != nil || sealed == nil {
		authError(w, http.StatusForbidden, "invalid_passkey_handoff")
		return
	}
	ciphertext, err := base64.RawURLEncoding.DecodeString(*sealed)
	if err != nil {
		authError(w, http.StatusForbidden, "invalid_passkey_handoff")
		return
	}
	plaintext, err := store.passkeySeal.Open(nil, nil, ciphertext, digest[:])
	var session passkeySession
	if err != nil || json.Unmarshal(plaintext, &session) != nil {
		authError(w, http.StatusForbidden, "invalid_passkey_handoff")
		return
	}
	actor := store.verifiedPasskeyIdentity(r, input.Organization, session.AccessToken)
	if actor == nil {
		store.revokeUndeliveredPasskeySession(r, session.AccessToken)
		authError(w, http.StatusForbidden, "invalid_passkey_handoff")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(struct {
		Session      passkeySession `json:"session"`
		UserID       string         `json:"userId"`
		Organization int64          `json:"organization"`
		RequiresMFA  bool           `json:"requiresMfa"`
	}{session, actor.UserID, input.Organization, actor.RequiresMFA})
}
