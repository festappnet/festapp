package main

import (
	"crypto/cipher"
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

const mfaChannelRoute = publicAuthPrefix + "/festapp/mfa/channel"

type channelMethod struct {
	Offer                 bool   `json:"offer"`
	Registration          bool   `json:"registration"`
	SignIn                bool   `json:"signIn"`
	SignInRevision        int64  `json:"signInRevision,omitempty"`
	RegistrationPilotUser string `json:"registrationPilotUser,omitempty"`
}

type channelPolicy struct {
	Platform string                   `json:"platform"`
	Methods  map[string]channelMethod `json:"methods"`
}

type channelStore struct {
	providerAuth string
	passkeySeal  cipher.AEAD
	origin       string
	token        string
	client       *http.Client
}

func newChannelStore(origin *url.URL, token string) *channelStore {
	return &channelStore{
		origin: origin.String(),
		token:  token,
		client: &http.Client{
			Timeout: 5 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}
}

func (store *channelStore) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodOptions {
		w.Header().Set("Allow", "GET, OPTIONS")
		authError(w, http.StatusMethodNotAllowed, "method_not_allowed")
		return
	}
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil || len(query) != 3 || len(query["client_id"]) != 1 ||
		len(query["organization"]) != 1 || len(query["redirect_uri"]) != 1 {
		authError(w, http.StatusBadRequest, "invalid_mfa_channel")
		return
	}
	organization, err := strconv.ParseInt(query.Get("organization"), 10, 64)
	origin, client, redirect := r.Header.Get("Origin"), query.Get("client_id"), query.Get("redirect_uri")
	if err != nil || organization <= 0 || len(origin) == 0 || len(origin) > 512 ||
		len(client) == 0 || len(client) > 128 || len(redirect) == 0 || len(redirect) > 2048 {
		authError(w, http.StatusBadRequest, "invalid_mfa_channel")
		return
	}
	policy, err := store.resolveChannel(r, client, organization, origin, redirect)
	if err != nil {
		authError(w, http.StatusServiceUnavailable, "mfa_channel_unavailable")
		return
	}
	if policy == nil {
		authError(w, http.StatusNotFound, "mfa_channel_not_found")
		return
	}
	setRegistrationHeaders(w, origin)
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		w.Header().Set("Access-Control-Allow-Headers", "apikey, authorization")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	for name, method := range policy.Methods {
		method.SignIn = method.SignIn && store.passkeySeal != nil
		if method.RegistrationPilotUser != "" {
			var actor struct {
				ID string `json:"id"`
			}
			recovery := false
			if bearer, ok := bearerToken(r.Header.Get("Authorization")); ok {
				status, body := store.providerRequest(r, http.MethodGet, "/user", nil)
				if status == http.StatusOK {
					_ = json.Unmarshal(body, &actor)
				}
				if actor.ID != "" && actor.ID != method.RegistrationPilotUser {
					var proof registrationActor
					recovery = store.rpc(r.Context(), "get_mfa_recovery_registration_actor_v1", bearer,
						map[string]any{"p_organization": organization}, &proof) == nil &&
						proof.Decision == "allowed" && proof.UserID == actor.ID
				}
			}
			if actor.ID != method.RegistrationPilotUser && !recovery {
				// At sign-in the account is discovered by the authenticator.
				// An optional login action reveals no account eligibility.
				method.Offer = method.Offer && name == "passkey" && method.SignIn &&
					r.Header.Get("Authorization") == ""
				method.Registration = false
			}
			method.RegistrationPilotUser = ""
		}
		method.SignInRevision = 0
		policy.Methods[name] = method
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(policy)
}

func (store *channelStore) resolveChannel(r *http.Request, client string, organization int64, origin, redirect string) (*channelPolicy, error) {
	var policy *channelPolicy
	err := store.rpc(r.Context(), "resolve_mfa_channel_policy_v1", store.token, map[string]any{
		"p_client_id": client, "p_organization": organization, "p_origin": origin, "p_redirect_uri": redirect,
	}, &policy)
	return policy, err
}
