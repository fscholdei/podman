package nixstore

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/sirupsen/logrus"
)

// Manager handles Nix store operations
type Manager struct {
	imagesJSONPath string
}

// NewManager creates a new Nix store manager
func NewManager() (*Manager, error) {
	// Find images.json in standard locations
	var imagesJSONPath string
	if configDir, err := os.UserConfigDir(); err == nil {
		userPath := filepath.Join(configDir, "podman", "images.json")
		logrus.Infof("Checking for images.json in %s", userPath)
		if _, err := os.Stat(userPath); err == nil {
			imagesJSONPath = userPath
		}
	}

	if imagesJSONPath == "" {
		systemPath := "/etc/podman/images.json"
		logrus.Infof("Checking for images.json in %s", systemPath)
		if _, err := os.Stat(systemPath); err == nil {
			imagesJSONPath = systemPath
		}
	}

	if imagesJSONPath == "" {
		logrus.Info("images.json not found, Nix store backend is disabled.")
		return &Manager{}, nil
	}

	logrus.Info("Nix store backend enabled, using mapping file: ", imagesJSONPath)

	return &Manager{imagesJSONPath: imagesJSONPath}, nil
}

// IsEnabled returns whether Nix store backend is enabled
func (m *Manager) IsEnabled() bool {
	return m.imagesJSONPath != ""
}

type ImageEntry string

// ResolveImage resolves an image name to its Nix store path
func (m *Manager) ResolveImage(imageName string) (ImageEntry, error) {
	if !m.IsEnabled() {
		return "", fmt.Errorf("Nix store backend is not enabled")
	}

	logrus.Infof("Resolving image %s using mapping file", imageName)

	data, err := os.ReadFile(m.imagesJSONPath)
	if err != nil {
		return "", fmt.Errorf("failed to read images.json: %w", err)
	}

	var rawMapping map[string]json.RawMessage
	if err := json.Unmarshal(data, &rawMapping); err != nil {
		return "", fmt.Errorf("failed to unmarshal images.json: %w", err)
	}

	rawImages, ok := rawMapping["images"]
	if !ok {
		return "", fmt.Errorf(`"images" key not found in images.json`)
	}

	var images map[string]json.RawMessage
	if err := json.Unmarshal(rawImages, &images); err != nil {
		return "", fmt.Errorf("failed to unmarshal images in images.json: %w", err)
	}

	imageEntries := make(map[string]ImageEntry)
	for name, rawEntry := range images {
		var path string
		if err := json.Unmarshal(rawEntry, &path); err == nil {
			imageEntries[name] = ImageEntry(path)
			continue
		}

		var structured struct {
			Rootfs string `json:"rootfs"`
		}
		if err := json.Unmarshal(rawEntry, &structured); err != nil {
			return "", fmt.Errorf("cannot unmarshal image entry %q from %q", name, string(rawEntry))
		}
		imageEntries[name] = ImageEntry(structured.Rootfs)
	}

	imageAttr := strings.TrimPrefix(imageName, "localhost/")
	imageAttr = strings.TrimPrefix(imageAttr, "nix/")

	entry, ok := imageEntries[imageAttr]
	if !ok {
		return "", fmt.Errorf("image %q not found in images.json", imageAttr)
	}

	return entry, nil
}
