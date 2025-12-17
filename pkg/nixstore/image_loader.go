package nixstore

import (
	"context"
	"fmt"
	"github.com/sirupsen/logrus"
	"go.podman.io/storage"
)

// ImageLoader handles loading images from Nix store into Podman storage
type ImageLoader struct {
	manager *Manager
	store   storage.Store
}

// NewImageLoader creates a new image loader
func NewImageLoader(manager *Manager, store storage.Store) *ImageLoader {
	return &ImageLoader{
		manager: manager,
		store:   store,
	}
}

// IsEnabled returns whether the Nix store integration is enabled
func (l *ImageLoader) IsEnabled() bool {
	return l.manager != nil && l.manager.IsEnabled()
}

// TryLoadFromNixStore attempts to load an image from the Nix store
// Returns the local image name if successful, empty string otherwise
func (l *ImageLoader) TryLoadFromNixStore(ctx context.Context, imageName string) (string, error) {
	if !l.IsEnabled() {
		return "", nil
	}

	logrus.Infof("Attempting to load image %s from Nix store", imageName)

	// Prefetch the image from Nix store
	nixImageName, err := l.manager.PrefetchImage(ctx, imageName)
	if err != nil {
		return "", fmt.Errorf("failed to prefetch image from Nix store: %w", err)
	}

	logrus.Infof("Successfully prefetched image from Nix store: %s", nixImageName)
	return nixImageName, nil
}
