package nixstore

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/sirupsen/logrus"
)

// Manager handles Nix store operations
type Manager struct {
	nixPath       string
	imagesNixPath string
}

// NewManager creates a new Nix store manager
func NewManager() (*Manager, error) {
	nixPath, err := exec.LookPath("nix")
	if err != nil {
		// If nix is not found, we don't enable the Nix store backend.
		// This is not a fatal error.
		logrus.Info("nix not found in PATH, Nix store backend is disabled.")
		return &Manager{nixPath: ""}, nil
	}

	// Find images.nix in standard locations
	var imagesNixPath string
	if configDir, err := os.UserConfigDir(); err == nil {
		userPath := filepath.Join(configDir, "podman", "images.nix")
		logrus.Infof("Checking for images.nix in %s", userPath)
		if _, err := os.Stat(userPath); err == nil {
			imagesNixPath = userPath
		}
	}

	if imagesNixPath == "" {
		systemPath := "/etc/podman/images.nix"
		logrus.Infof("Checking for images.nix in %s", systemPath)
		if _, err := os.Stat(systemPath); err == nil {
			imagesNixPath = systemPath
		}
	}

	if imagesNixPath == "" {
		logrus.Info("images.nix not found, Nix store backend is disabled.")
		return &Manager{nixPath: ""}, nil
	}

	logrus.Info("Nix store backend enabled, found nix at: ", nixPath)
	logrus.Infof("Using Nix images file: %s", imagesNixPath)

	return &Manager{nixPath: nixPath, imagesNixPath: imagesNixPath}, nil
}

// IsEnabled returns whether Nix store backend is enabled
func (m *Manager) IsEnabled() bool {
	return m.nixPath != "" && m.imagesNixPath != ""
}

// ResolveImage resolves an image name to its Nix store path
func (m *Manager) ResolveImage(ctx context.Context, imageName string) (string, error) {
	if !m.IsEnabled() {
		return "", fmt.Errorf("Nix store backend is not enabled")
	}

	logrus.Infof("Resolving image %s using nix", imageName)

	// The expression to evaluate, which imports the images file, selects the attribute, and pulls the image
	imageAttr := strings.TrimPrefix(imageName, "localhost/")
	nixExpr := fmt.Sprintf("with import <nixpkgs> {}; (pkgs.dockerTools.pullImage ((import %s).%s))", m.imagesNixPath, imageAttr)

	cmd := exec.CommandContext(ctx, m.nixPath, "build", "--impure", "--expr", nixExpr, "--print-out-paths")

	logrus.Debugf("Running: %s", cmd.String())

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("nix build failed for image %q: %w, output: %s", imageName, err, string(output))
	}

	storePath := strings.TrimSpace(string(output))
	if storePath == "" {
		return "", fmt.Errorf("nix build for image %q produced an empty store path", imageName)
	}

	// nix build can print other things to stdout, so we take the last line
	lines := strings.Split(storePath, "\n")
	return lines[len(lines)-1], nil
}
