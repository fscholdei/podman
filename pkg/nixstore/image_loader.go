package nixstore

import (
	"context"
	"fmt"

	"github.com/sirupsen/logrus"
	"go.podman.io/common/libimage"
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

// ResolveImage resolves an image name to its Nix store path
func (l *ImageLoader) ResolveImage(ctx context.Context, imageName string) (string, error) {
	return l.manager.ResolveImage(ctx, imageName)
}

// LoadImage loads an image from the Nix store into Podman's storage
func (l *ImageLoader) LoadImage(ctx context.Context, imageName, storePath string) (*libimage.Image, error) {
	if !l.IsEnabled() {
		return nil, fmt.Errorf("Nix store backend is not enabled")
	}

	logrus.Infof("Loading image %s from Nix store path %s", imageName, storePath)

	imageRuntime, err := libimage.RuntimeFromStore(l.store, &libimage.RuntimeOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to create libimage runtime: %w", err)
	}

	loadOptions := &libimage.LoadOptions{}
	ids, err := imageRuntime.Load(ctx, storePath, loadOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to load image from directory into storage: %w", err)
	}
	if len(ids) == 0 {
		return nil, fmt.Errorf("no image loaded from Nix store path %s", storePath)
	}

	// Find the loaded image by ID
	loadedImage, _, err := imageRuntime.LookupImage(ids[0], nil)
	if err != nil {
		return nil, fmt.Errorf("failed to find loaded image %s: %w", ids[0], err)
	}
	if loadedImage == nil {
		return nil, fmt.Errorf("image with ID %s not found after load", ids[0])
	}

	// Tag the image with the requested name if not already tagged
	if err := loadedImage.Tag(imageName); err != nil {
		return nil, fmt.Errorf("failed to tag image %s with name %s: %w", loadedImage.ID(), imageName, err)
	}

	logrus.Infof("Successfully loaded and tagged image %s as %s from Nix store", loadedImage.ID(), imageName)
	return loadedImage, nil
}

// TryLoadFromNixStore attempts to load an image from the Nix store
// Returns the local image name if successful, empty string otherwise
func (l *ImageLoader) TryLoadFromNixStore(ctx context.Context, imageName string) (string, error) {
	if !l.IsEnabled() {
		return "", nil
	}

	logrus.Infof("Attempting to load image %s from Nix store", imageName)

	// Instead of PrefetchImage, use ResolveImage to get the store path
	storePath, err := l.manager.ResolveImage(ctx, imageName)
	if err != nil {
		return "", fmt.Errorf("failed to resolve image from Nix store: %w", err)
	}
	if storePath == "" {
		return "", fmt.Errorf("no Nix store path found for image %s", imageName)
	}

	// Load the image from the store path into Podman's storage
	loadedImage, err := l.LoadImage(ctx, imageName, storePath)
	if err != nil {
		return "", fmt.Errorf("failed to load image from Nix store path %s: %w", storePath, err)
	}

	// Tag the image with the original name
	if err := loadedImage.Tag(imageName); err != nil {
		return "", fmt.Errorf("failed to tag image: %w", err)
	}

	logrus.Infof("Successfully loaded image %s from Nix store", imageName)
	return loadedImage.Names()[0], nil
}
