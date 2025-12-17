package nixstore

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/sirupsen/logrus"
)

// NixPrefetchResult represents the output from nix-prefetch-docker
type NixPrefetchResult struct {
	ImageName   string `json:"imageName"`
	ImageDigest string `json:"imageDigest"`
	Sha256      string `json:"sha256"`
	ImageTag    string `json:"imageTag"`
}

// Manager handles Nix store operations
type Manager struct {
	nixPrefetchDockerPath string
	cacheDir              string
}

// NewManager creates a new Nix store manager
func NewManager() (*Manager, error) {
	path, err := exec.LookPath("nix-prefetch-docker")
	if err != nil {
		// If nix-prefetch-docker is not found, we don't enable the Nix store backend.
		// This is not a fatal error.
		logrus.Info("nix-prefetch-docker not found in PATH, Nix store backend is disabled.")
		return &Manager{nixPrefetchDockerPath: ""}, nil
	}

	// Initialize cache directory
	cacheDir := ""
	userCacheDir, err := os.UserCacheDir()
	if err == nil {
		cacheDir = filepath.Join(userCacheDir, "podman", "nixstore")
		if err := os.MkdirAll(cacheDir, 0755); err != nil {
			logrus.Warnf("Failed to create Nix store cache directory: %v", err)
			cacheDir = "" // Disable caching if directory creation fails
		}
	} else {
		logrus.Warnf("Failed to get user cache directory: %v", err)
	}

	logrus.Info("Nix store backend enabled, found nix-prefetch-docker at: ", path)
	if cacheDir != "" {
		logrus.Infof("Nix store cache enabled at: %s", cacheDir)
	}

	return &Manager{nixPrefetchDockerPath: path, cacheDir: cacheDir}, nil
}

// IsEnabled returns whether Nix store backend is enabled
func (m *Manager) IsEnabled() bool {
	return m.nixPrefetchDockerPath != ""
}

// PrefetchImage fetches an image from Docker registry into Nix store
func (m *Manager) PrefetchImage(ctx context.Context, imageName string) (string, error) {
	if !m.IsEnabled() {
		return "", fmt.Errorf("Nix store backend is not enabled")
	}

	// If the image is a short name, assume the user wants to pull from
	// docker.io, which is the default for nix-prefetch-docker.
	if !strings.Contains(imageName, "/") {
		imageName = "docker.io/library/" + imageName
		logrus.Infof("Short name detected, resolving to %s for Nix store", imageName)
	}

	// Check cache first
	if m.cacheDir != "" {
		cacheKey := strings.ReplaceAll(imageName, "/", "_")
		cacheFile := filepath.Join(m.cacheDir, cacheKey+".json")
		if data, err := os.ReadFile(cacheFile); err == nil {
			var result NixPrefetchResult
			if err := json.Unmarshal(data, &result); err == nil {
				logrus.Infof("Found cached Nix store info for %s", imageName)
				return result.ImageName, nil
			}
		}
	}

	logrus.Infof("Prefetching image %s using nix-prefetch-docker", imageName)

	// Parse image name to extract repository and tag
	parts := strings.Split(imageName, ":")
	repository := parts[0]
	tag := "latest"
	if len(parts) > 1 {
		tag = parts[1]
	}

	// Remove registry prefix if present (nix-prefetch-docker doesn't need it for docker.io)
	repository = strings.TrimPrefix(repository, "docker.io/")

	// Build nix-prefetch-docker command
	// nix-prefetch-docker --image-name <name> --image-tag <tag> --json
	cmd := exec.CommandContext(ctx, m.nixPrefetchDockerPath,
		"--image-name", repository,
		"--image-tag", tag,
		"--json")

	logrus.Debugf("Running: %s", cmd.String())

	output, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("nix-prefetch-docker failed: %w, stderr: %s", err, string(ee.Stderr))
		}
		return "", fmt.Errorf("nix-prefetch-docker failed: %w", err)
	}

	var result NixPrefetchResult
	if err := json.Unmarshal(output, &result); err != nil {
		return "", fmt.Errorf("failed to parse nix-prefetch-docker output: %w", err)
	}

	// Save to cache
	if m.cacheDir != "" {
		cacheKey := strings.ReplaceAll(imageName, "/", "_")
		cacheFile := filepath.Join(m.cacheDir, cacheKey+".json")
		data, err := json.MarshalIndent(&result, "", "  ")
		if err != nil {
			logrus.Warnf("Failed to marshal nix-prefetch-docker result for caching: %v", err)
		} else {
			if err := os.WriteFile(cacheFile, data, 0644); err != nil {
				logrus.Warnf("Failed to write to Nix store cache: %v", err)
			}
		}
	}

	// The result gives us the information to build a Nix derivation, which when built
	// will produce the image in the Nix store. The image name podman should use is
	// what nix-prefetch-docker returns.
	return result.ImageName, nil
}
