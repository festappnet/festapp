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
	Offer          bool  `json:"offer"`
	Registration   bool  `json:"registration"`
	SignIn         bool  `json:"signIn"`
	SignInRevision int64 `json:"signInRevision,omitempty"`
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
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
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
	for name, method := range policy.Methods {
		method.SignIn = method.SignIn && store.passkeySeal != nil
		method.SignInRevision = 0
		policy.Methods[name] = method
	}
	w.Header().Set("Vary", "Origin")
	w.Header().Set("Access-Control-Allow-Origin", origin)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(policy)
}

func (store *channelStore) resolveChannel(r *http.Request, client string, organization int64, origin, redirect string) (*channelPolicy, error) {
	var policy *channelPolicy
	err := store.rpc(r.Context(), "resolve_mfa_channel_policy_v1", store.token, map[string]any{
		"p_client_id": client, "p_organization": organization, "p_origin": origin, "p_redirect_uri": redirect,
	}, &policy)
	return policy, err
}
