// The WebAuthn admission boundary runs in front of the pinned GoTrue.
// GoTrue still validates the entire ceremony, including signatures and origin.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path"
	"strings"
	"time"

	"github.com/go-webauthn/webauthn/protocol"
)

const maxAuthBody = 64 * 1024
const publicAuthPrefix = "/auth/v1"

type credentialEnvelope struct {
	Credential json.RawMessage `json:"credential"`
	WebAuthn   *struct {
		Type       string          `json:"type"`
		Credential json.RawMessage `json:"credential_response"`
	} `json:"webauthn"`
}

func authError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"code": code, "msg": code})
}

var errCredentialOrigin = errors.New("WebAuthn credential origin does not match the channel")

func hasUserVerification(credential json.RawMessage, registration bool, origin string) (bool, error) {
	if registration {
		parsed, err := protocol.ParseCredentialCreationResponseBytes(credential)
		if err != nil {
			return false, err
		}
		if origin != "" && (parsed.Response.CollectedClientData.Origin != origin || parsed.Response.CollectedClientData.CrossOrigin) {
			return false, errCredentialOrigin
		}
		return parsed.Response.AttestationObject.AuthData.Flags.HasUserVerified(), nil
	}
	parsed, err := protocol.ParseCredentialRequestResponseBytes(credential)
	if err != nil {
		return false, err
	}
	if origin != "" && (parsed.Response.CollectedClientData.Origin != origin || parsed.Response.CollectedClientData.CrossOrigin) {
		return false, errCredentialOrigin
	}
	return parsed.Response.AuthenticatorData.Flags.HasUserVerified(), nil
}

func webAuthnAdmission(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		canonicalPath := strings.TrimSuffix(r.URL.Path, "/")
		if r.URL.EscapedPath() != r.URL.Path || canonicalPath != path.Clean(r.URL.Path) {
			authError(w, http.StatusBadRequest, "invalid_auth_path")
			return
		}
		if canonicalPath != publicAuthPrefix && !strings.HasPrefix(canonicalPath, publicAuthPrefix+"/") {
			authError(w, http.StatusNotFound, "invalid_auth_path")
			return
		}
		canonicalPath = strings.TrimPrefix(canonicalPath, publicAuthPrefix)

		bits := strings.Split(canonicalPath, "/")
		factorVerification := len(bits) == 4 && bits[1] == "factors" && bits[3] == "verify"
		passkeyRegistration := canonicalPath == "/passkeys/registration/verify"
		passkeyAuthentication := canonicalPath == "/passkeys/authentication/verify"
		if r.Method != http.MethodPost || !(factorVerification || passkeyRegistration || passkeyAuthentication) {
			next.ServeHTTP(w, r)
			return
		}

		bounded := http.MaxBytesReader(w, r.Body, maxAuthBody)
		body, err := io.ReadAll(bounded)
		bounded.Close()
		if err != nil {
			authError(w, http.StatusRequestEntityTooLarge, "invalid_auth_body_size")
			return
		}
		var envelope credentialEnvelope
		if err := json.Unmarshal(body, &envelope); err != nil {
			authError(w, http.StatusBadRequest, "invalid_auth_body")
			return
		}

		// GoTrue's TOTP and phone handlers verify a code. Its WebAuthn
		// factor handler requires a non-nil webauthn envelope.
		if !factorVerification || envelope.WebAuthn != nil {
			credential, registration := envelope.Credential, passkeyRegistration
			if factorVerification {
				switch envelope.WebAuthn.Type {
				case "create":
					registration = true
				case "request":
					registration = false
				default:
					authError(w, http.StatusBadRequest, "invalid_webauthn_ceremony")
					return
				}
				credential = envelope.WebAuthn.Credential
			}
			var origin string
			if factorVerification {
				origin = r.Header.Get("Origin")
			}
			verified, err := hasUserVerification(credential, registration, origin)
			if errors.Is(err, errCredentialOrigin) {
				authError(w, http.StatusForbidden, "invalid_webauthn_origin")
				return
			}
			if err != nil {
				authError(w, http.StatusBadRequest, "invalid_webauthn_credential")
				return
			}
			if !verified {
				authError(w, http.StatusForbidden, "webauthn_user_verification_required")
				return
			}
		}

		// Keep the original bytes for GoTrue's independent verification.
		r.Body = io.NopCloser(bytes.NewReader(body))
		next.ServeHTTP(w, r)
	})
}

func loopbackOrigin(raw string) (*url.URL, error) {
	target, err := url.Parse(raw)
	if err != nil || target.Scheme != "http" || target.Hostname() != "127.0.0.1" || target.Port() == "" ||
		target.Path != "" || target.RawQuery != "" || target.Fragment != "" || target.User != nil {
		return nil, fmt.Errorf("an explicit loopback origin is required")
	}
	return target, nil
}

func main() {
	listen := flag.String("listen", "127.0.0.1:0", "IPv4 loopback listen address")
	upstream := flag.String("upstream", "", "loopback Auth upstream origin")
	direct := flag.Bool("direct-gotrue", false, "strip the Auth prefix for a disposable GoTrue without Envoy")
	qualification := flag.Bool("qualify-provider", false, "disposable GoTrue protocol qualification")
	policyOrigin := flag.String("policy-origin", "", "loopback origin serving /rest/v1")
	flag.Parse()
	if *qualification && !*direct {
		log.Fatal("provider qualification requires a disposable direct GoTrue")
	}
	if !*qualification && *policyOrigin == "" {
		log.Fatal("the public Auth gateway requires its account policy origin")
	}

	target, err := loopbackOrigin(*upstream)
	if err != nil {
		log.Fatal("invalid Auth upstream")
	}
	var channel *channelStore
	if *policyOrigin != "" {
		policyTarget, err := loopbackOrigin(*policyOrigin)
		token := os.Getenv("FESTAPP_AUTH_POLICY_SERVICE_TOKEN")
		if err != nil || token == "" || len(token) > 8192 || strings.ContainsAny(token, " \r\n") {
			log.Fatal("valid loopback policy origin and protected service token are required")
		}
		channel = newChannelStore(policyTarget, token)
		if key := os.Getenv("FESTAPP_PASSKEY_HANDOFF_KEY"); key != "" {
			channel.passkeySeal, err = newPasskeySeal(key)
			if err != nil {
				log.Fatal("invalid protected passkey handoff key")
			}
		}
		channel.providerAuth = target.String()
		if !*direct {
			channel.providerAuth += publicAuthPrefix
		}
	}
	host, _, err := net.SplitHostPort(*listen)
	if err != nil || host != "127.0.0.1" {
		log.Fatal("the auth ingress must listen on IPv4 loopback")
	}
	listener, err := net.Listen("tcp4", *listen)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(listener.Addr().String())
	var proxy http.Handler = httputil.NewSingleHostReverseProxy(target)
	if *direct {
		proxy = http.StripPrefix(publicAuthPrefix, proxy)
	}
	if !*qualification {
		proxy = channel.protectPublicAuth(proxy)
	}
	server := &http.Server{
		Handler: webAuthnAdmission(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == mfaChannelRoute && channel != nil {
				channel.ServeHTTP(w, r)
				return
			}
			if channel != nil {
				switch r.URL.Path {
				case beginMFARegistrationRoute, claimMFARegistrationRoute, removeMFAFactorRoute,
					listPasskeysRoute, renamePasskeyRoute, removePasskeyRoute,
					enrollTOTPRouter, verifyTOTPRouter,
					enrollWebAuthnRoute, challengeWebAuthnRoute, verifyWebAuthnRoute,
					optionsPasskeyRegistrationRoute, verifyPasskeyRegistrationRoute,
					optionsPasskeySignInRoute, verifyPasskeySignInRoute, exchangePasskeySignInRoute:
					channel.registrationHandoff(w, r)
					return
				}
			}
			if strings.HasPrefix(r.URL.Path, publicAuthPrefix+"/festapp/") {
				authError(w, http.StatusNotFound, "unknown_auth_operation")
				return
			}
			proxy.ServeHTTP(w, r)
		})),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Fatal(server.Serve(listener))
}
