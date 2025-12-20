package libpod

import (
	"context"
	"fmt"
	"go.podman.io/common/libimage"
)

type Image struct {
	*libimage.Image
	runtime *Runtime
}

func (r *Runtime) newImage(img *libimage.Image) *Image {
	return &Image{
		Image:   img,
		runtime: r,
	}
}

func (r *Runtime) getImage(ctx context.Context, name string) (*libimage.Image, error) {
	if r.nixImageLoader != nil && r.nixImageLoader.IsEnabled() {
		if storePath, err := r.nixImageLoader.ResolveImage(ctx, name); err == nil {
			image, err := r.nixImageLoader.LoadImage(ctx, name, storePath)
			if err != nil {
				return nil, fmt.Errorf("failed to load image from nix store: %w", err)
			}
			return image, nil
		}
	}
	return nil, fmt.Errorf("image resolution not implemented")
}

func (r *Runtime) GetImage(ctx context.Context, name string) (*Image, error) {
	img, err := r.getImage(ctx, name)
	if err != nil {
		return nil, err
	}
	return r.newImage(img), nil
}

func (r *Runtime) GetImages(ctx context.Context) ([]*Image, error) {
	imgs, err := r.libimageRuntime.ListImages(ctx, nil)
	if err != nil {
		return nil, err
	}
	images := make([]*Image, len(imgs))
	for i := range imgs {
		images[i] = r.newImage(imgs[i])
	}
	return images, nil
}

func (r *Runtime) LoadImage(ctx context.Context, path string, options *libimage.LoadOptions) ([]string, error) {
	return r.libimageRuntime.Load(ctx, path, options)
}

// RemoveImage removes an image from the local store.
func (r *Runtime) RemoveImage(ctx context.Context, image *Image) error {
	reports, errs := r.libimageRuntime.RemoveImages(ctx, []string{image.ID()}, nil)
	_ = reports // ignore reports for now
	for _, err := range errs {
		if err != nil {
			return err
		}
	}
	return nil
}
