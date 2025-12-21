package nixstore

import (
	"context"
	"fmt"
	"strings"

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

	// Tag the image with the requested name, adding nix/ prefix if it's not there
	nixImageName := strings.TrimPrefix(imageName, "localhost/")
	if !strings.HasPrefix(nixImageName, "nix/") {
		nixImageName = "nix/" + nixImageName
	}
	if err := loadedImage.Tag(nixImageName); err != nil {
		return nil, fmt.Errorf("failed to tag image %s with name %s: %w", loadedImage.ID(), nixImageName, err)
	}

	logrus.Infof("Successfully loaded and tagged image %s as %s from Nix store", loadedImage.ID(), nixImageName)
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

	// The image is now loaded and tagged. We need to return one of its names.
	// The tag with nix/ prefix should be preferred.
	for _, name := range loadedImage.Names() {
		if strings.HasPrefix(name, "nix/") {
			return name, nil
		}
	}

	// Fallback to the first name if no nix/ prefix is found (should not happen)
	if len(loadedImage.Names()) > 0 {
		return loadedImage.Names()[0], nil
	}

	return "", fmt.Errorf("loaded image %s has no names", loadedImage.ID())
}
