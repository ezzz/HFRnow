package stockage

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ChargerCleIP lit la clé des empreintes d'IP (32 octets, fichier à part, hors de la base). Si le fichier
// manque et que creer est vrai, il est créé en 0600 ; après la fermeture, creer est faux : la clé détruite
// ne revient jamais.
func ChargerCleIP(dossier string, creer bool) ([]byte, error) {
	chemin := filepath.Join(dossier, FichierCleIP)
	cle, err := os.ReadFile(chemin)
	if err == nil {
		if len(cle) != tailleCleIP {
			return nil, fmt.Errorf("%s : %d octets au lieu de %d", chemin, len(cle), tailleCleIP)
		}
		return cle, nil
	}
	if !errors.Is(err, os.ErrNotExist) || !creer {
		return nil, err
	}
	cle = make([]byte, tailleCleIP)
	if _, err := rand.Read(cle); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(chemin, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return nil, err
	}
	if _, err := f.Write(cle); err != nil {
		f.Close()
		return nil, err
	}
	return cle, f.Close()
}

// EmpreinteIP calcule l'empreinte d'une adresse : HMAC-SHA-256 sous la clé, en hexadécimal.
func EmpreinteIP(cle []byte, ip string) string {
	m := hmac.New(sha256.New, cle)
	m.Write([]byte(ip))
	return hex.EncodeToString(m.Sum(nil))
}

// EmpreinteJeton calcule l'empreinte d'un jeton : SHA-256 en hexadécimal.
func EmpreinteJeton(jeton string) string {
	h := sha256.Sum256([]byte(strings.ToLower(jeton)))
	return hex.EncodeToString(h[:])
}
