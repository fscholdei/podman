package nixstore

import (
	"context"
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

// ImageEntry represents the mapping from image names to Nix store paths
type ImageEntry struct {
	Rootfs   string `json:"rootfs"`
	Manifest string `json:"manifest"`
	Config   string `json:"config"`
}

type ImageMapping struct {
	Images map[string]ImageEntry `json:"images"`
}

// ResolveImage resolves an image name to its Nix store path
func (m *Manager) ResolveImage(ctx context.Context, imageName string) (ImageEntry, error) {
	if !m.IsEnabled() {
		return ImageEntry{}, fmt.Errorf("Nix store backend is not enabled")
	}

	logrus.Infof("Resolving image %s using mapping file", imageName)

	// Read the mapping file
	data, err := os.ReadFile(m.imagesJSONPath)
	if err != nil {
		return ImageEntry{}, fmt.Errorf("failed to read images.json: %w", err)
	}

	// Unmarshal the JSON
	var mapping ImageMapping
	if err := json.Unmarshal(data, &mapping); err != nil {
		return ImageEntry{}, fmt.Errorf("failed to unmarshal images.json: %w", err)
	}

	// The expression to evaluate, which imports the images file, selects the attribute, and pulls the image
	imageAttr := imageName
	if strings.HasPrefix(imageName, "localhost/") {
		imageAttr = strings.TrimPrefix(imageName, "localhost/")
	} else if strings.HasPrefix(imageName, "nix/") {
		imageAttr = strings.TrimPrefix(imageName, "nix/")
	}

	// Look up the image in the mapping
	entry, ok := mapping.Images[imageAttr]
	if !ok {
		return ImageEntry{}, fmt.Errorf("image %q not found in images.json", imageAttr)
	}

	return entry, nil
}
