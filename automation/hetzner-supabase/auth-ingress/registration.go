package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

const beginMFARegistrationRoute = publicAuthPrefix + "/festapp/mfa/registration/start"
const claimMFARegistrationRoute = publicAuthPrefix + "/festapp/mfa/registration/claim"

var pkceVerifier = regexp.MustCompile(`^[A-Za-z0-9._~-]{43,128}$`)
var opaqueCode = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

func enrollmentFactorName(name string) string {
	if trimmed := strings.TrimSpace(name); trimmed != "" {
		return trimmed
	}
	// GoTrue compares names across all factor types, including empty strings.
	return "Festapp #" + rand.Text()[:26]
}

type registrationActor struct {
	Decision       string `json:"decision"`
	UserID         string `json:"userId"`
	SessionID      string `json:"sessionId"`
	Recovery       bool   `json:"-"`
	PasswordProven bool   `json:"passwordProven"`
}

type beginRegistration struct {
	ClientID     string `json:"clientId"`
	Organization int64  `json:"organization"`
	RedirectURI  string `json:"redirectUri"`
	Method       string `json:"method"`
	Challenge    string `json:"codeChallenge"`
	RecoveryCode string `json:"recoveryCode"`
	InPlace      bool   `json:"inPlace"`
}

type claimRegistration struct {
	Organization int64  `json:"organization"`
	Code         string `json:"code"`
	Verifier     string `json:"codeVerifier"`
	Recovery     bool   `json:"recovery"`
}

type registrationReceipt struct {
	ID     string `json:"id"`
	Method string `json:"method"`
}

func (store *channelStore) rpc(ctx context.Context, name, token string, args any, result any) error {
	payload, err := json.Marshal(args)
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, store.origin+"/rest/v1/rpc/"+name, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+token)
	// Envoy uses the internal API key for routing. PostgreSQL authorization
	// follows the original bearer token for actor lookups.
	request.Header.Set("apikey", store.token)
	response, err := store.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		var failure struct {
			Code string `json:"code"`
		}
		if json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&failure) == nil &&
			regexp.MustCompile(`^[A-Z0-9]{5,12}$`).MatchString(failure.Code) {
			return errors.New("policy RPC refused (" + failure.Code + ")")
		}
		return errors.New("policy RPC refused")
	}
	return json.NewDecoder(io.LimitReader(response.Body, 70*1024)).Decode(result)
}

func (store *channelStore) registrationActor(w http.ResponseWriter, r *http.Request, organization *int64, recovery bool) *registrationActor {
	bearer, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		authError(w, http.StatusUnauthorized, "invalid_session")
		return nil
	}
	var actor registrationActor
	procedure := "get_mfa_registration_actor_v1"
	if recovery {
		procedure = "get_mfa_recovery_registration_actor_v1"
	}
	if err := store.rpc(r.Context(), procedure, bearer,
		map[string]*int64{"p_organization": organization}, &actor); err != nil {
		authError(w, http.StatusUnauthorized, "invalid_session")
		return nil
	}
	if actor.Decision != "allowed" || actor.UserID == "" || actor.SessionID == "" {
		authError(w, http.StatusForbidden, "registration_proof_required")
		return nil
	}
	actor.Recovery = recovery
	return &actor
}

func validHTTPSOrigin(raw string) bool {
	origin, err := url.Parse(raw)
	return err == nil && origin.Scheme == "https" && origin.Hostname() != "" && origin.User == nil &&
		origin.Path == "" && origin.RawQuery == "" && origin.Fragment == ""
}

func readRegistrationBody(w http.ResponseWriter, r *http.Request, result any) bool {
	body := http.MaxBytesReader(w, r.Body, maxAuthBody)
	defer body.Close()
	decoder := json.NewDecoder(body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(result); err != nil || decoder.Decode(&struct{}{}) != io.EOF {
		authError(w, http.StatusBadRequest, "invalid_mfa_registration")
		return false
	}
	return true
}

func setRegistrationHeaders(w http.ResponseWriter, origin string) {
	w.Header().Set("Vary", "Origin")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Access-Control-Allow-Origin", origin)
}

func (store *channelStore) registrationHandoff(w http.ResponseWriter, r *http.Request) {
	origin := r.Header.Get("Origin")
	if !validHTTPSOrigin(origin) {
		authError(w, http.StatusForbidden, "invalid_mfa_channel")
		return
	}
	if r.Method == http.MethodOptions {
		setRegistrationHeaders(w, origin)
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		w.Header().Set("Access-Control-Allow-Headers", "apikey, authorization, content-type")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST, OPTIONS")
		authError(w, http.StatusMethodNotAllowed, "method_not_allowed")
		return
	}
	switch r.URL.Path {
	case beginMFARegistrationRoute:
		store.startRegistration(w, r, origin)
	case claimMFARegistrationRoute:
		store.claimRegistration(w, r, origin)
	case removeMFAFactorRoute:
		store.removeMFAFactor(w, r, origin)
	case listPasskeysRoute, renamePasskeyRoute, removePasskeyRoute:
		store.managePasskeys(w, r, origin)
	case enrollTOTPRouter, verifyTOTPRouter:
		store.totpRegistration(w, r, origin)
	case enrollWebAuthnRoute, challengeWebAuthnRoute, verifyWebAuthnRoute:
		store.webAuthnRegistration(w, r, origin)
	case optionsPasskeyRegistrationRoute, verifyPasskeyRegistrationRoute:
		store.passkeyRegistration(w, r, origin)
	case optionsPasskeySignInRoute, verifyPasskeySignInRoute, exchangePasskeySignInRoute:
		store.passkeySignIn(w, r, origin)
	}
}

func (store *channelStore) startRegistration(w http.ResponseWriter, r *http.Request, origin string) {
	var input beginRegistration
	if !readRegistrationBody(w, r, &input) {
		return
	}
	destination, err := url.Parse(input.RedirectURI)
	if err != nil || destination.Scheme != "https" || destination.Hostname() == "" || destination.User != nil ||
		destination.RawQuery != "" || destination.Fragment != "" || len(input.RedirectURI) > 2048 ||
		input.Organization <= 0 || len(input.ClientID) == 0 || len(input.ClientID) > 128 ||
		!opaqueCode.MatchString(input.Challenge) ||
		(input.RecoveryCode != "" && !opaqueCode.MatchString(input.RecoveryCode)) {
		authError(w, http.StatusBadRequest, "invalid_mfa_registration")
		return
	}
	actor := store.registrationActor(w, r, &input.Organization, input.RecoveryCode != "")
	if actor == nil {
		return
	}
	var secret [32]byte
	rand.Read(secret[:])
	code := base64.RawURLEncoding.EncodeToString(secret[:])
	digest := sha256.Sum256([]byte(code))
	var issued bool
	args := map[string]any{
		"p_user": actor.UserID, "p_session": actor.SessionID, "p_client_id": input.ClientID,
		"p_organization": input.Organization, "p_origin": origin, "p_redirect_uri": input.RedirectURI,
		"p_method": input.Method, "p_code_hash": hex.EncodeToString(digest[:]), "p_challenge": input.Challenge,
	}
	if actor.Recovery {
		recovery := sha256.Sum256([]byte(input.RecoveryCode))
		args["p_recovery_hash"] = hex.EncodeToString(recovery[:])
	}
	err = store.rpc(r.Context(), "issue_mfa_registration_handoff_v1", store.token, args, &issued)
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if !issued {
		authError(w, http.StatusForbidden, "registration_unavailable")
		return
	}
	setRegistrationHeaders(w, origin)
	destination.RawQuery = url.Values{"mfa_code": {code}}.Encode()
	if input.InPlace {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"callback": destination.String()})
		return
	}
	w.Header().Set("Location", destination.String())
	w.WriteHeader(http.StatusSeeOther)
}

func (store *channelStore) claimRegistration(w http.ResponseWriter, r *http.Request, origin string) {
	var input claimRegistration
	if !readRegistrationBody(w, r, &input) {
		return
	}
	if input.Organization <= 0 || !opaqueCode.MatchString(input.Code) || !pkceVerifier.MatchString(input.Verifier) {
		authError(w, http.StatusBadRequest, "invalid_mfa_registration")
		return
	}
	actor := store.registrationActor(w, r, &input.Organization, input.Recovery)
	if actor == nil {
		return
	}
	code := sha256.Sum256([]byte(input.Code))
	verifier := sha256.Sum256([]byte(input.Verifier))
	var receipt *registrationReceipt
	err := store.rpc(r.Context(), "claim_mfa_registration_handoff_v1", store.token, map[string]any{
		"p_user": actor.UserID, "p_session": actor.SessionID, "p_organization": input.Organization, "p_origin": origin,
		"p_code_hash": hex.EncodeToString(code[:]), "p_challenge": base64.RawURLEncoding.EncodeToString(verifier[:]),
		"p_recovery": input.Recovery,
	}, &receipt)
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if receipt == nil {
		authError(w, http.StatusForbidden, "registration_unavailable")
		return
	}
	setRegistrationHeaders(w, origin)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(receipt)
}
