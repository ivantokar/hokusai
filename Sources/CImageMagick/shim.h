#ifndef CIMAGEMAGICK_SHIM_H
#define CIMAGEMAGICK_SHIM_H

// Define required ImageMagick macros
#define MAGICKCORE_HDRI_ENABLE 1
#define MAGICKCORE_QUANTUM_DEPTH 16
#define MAGICKCORE_CHANNEL_MASK_DEPTH 32

// Try ImageMagick 7 path first, then fall back to ImageMagick 6
#if __has_include(<MagickWand/MagickWand.h>)
#include <MagickWand/MagickWand.h>
#elif __has_include(<wand/MagickWand.h>)
#include <wand/MagickWand.h>
#else
#error "Could not find MagickWand headers"
#endif

// MARK: - Lifecycle Management

static inline void hokusai_magick_init() {
    MagickWandGenesis();
}

static inline void hokusai_magick_terminate() {
    MagickWandTerminus();
}

// MARK: - Wand Creation

static inline MagickWand* hokusai_new_wand() {
    return NewMagickWand();
}

static inline void hokusai_destroy_wand(MagickWand *wand) {
    if (wand) {
        DestroyMagickWand(wand);
    }
}

static inline DrawingWand* hokusai_new_drawing_wand() {
    return NewDrawingWand();
}

static inline void hokusai_destroy_drawing_wand(DrawingWand *wand) {
    if (wand) {
        DestroyDrawingWand(wand);
    }
}

static inline PixelWand* hokusai_new_pixel_wand() {
    return NewPixelWand();
}

static inline void hokusai_destroy_pixel_wand(PixelWand *wand) {
    if (wand) {
        DestroyPixelWand(wand);
    }
}

// MARK: - Image Loading

static inline MagickBooleanType hokusai_read_image(MagickWand *wand, const char *filename) {
    return MagickReadImage(wand, filename);
}

static inline MagickBooleanType hokusai_read_image_blob(
    MagickWand *wand,
    const void *blob,
    const size_t length
) {
    return MagickReadImageBlob(wand, blob, length);
}

// MARK: - Image Saving

static inline MagickBooleanType hokusai_write_image(MagickWand *wand, const char *filename) {
    return MagickWriteImage(wand, filename);
}

static inline unsigned char* hokusai_get_image_blob(MagickWand *wand, size_t *length) {
    return MagickGetImageBlob(wand, length);
}

static inline void* hokusai_relinquish_memory(void *resource) {
    return MagickRelinquishMemory(resource);
}

// MARK: - Image Properties

static inline size_t hokusai_get_image_width(MagickWand *wand) {
    return MagickGetImageWidth(wand);
}

static inline size_t hokusai_get_image_height(MagickWand *wand) {
    return MagickGetImageHeight(wand);
}

static inline const char* hokusai_get_image_format(MagickWand *wand) {
    return MagickGetImageFormat(wand);
}

static inline MagickBooleanType hokusai_set_image_format(MagickWand *wand, const char *format) {
    return MagickSetImageFormat(wand, format);
}

// MARK: - Text Rendering - Font Configuration

static inline void hokusai_draw_set_font(DrawingWand *wand, const char *font_name) {
    DrawSetFont(wand, font_name);
}

static inline void hokusai_draw_set_font_size(DrawingWand *wand, double pointsize) {
    DrawSetFontSize(wand, pointsize);
}

static inline void hokusai_draw_set_text_kerning(DrawingWand *wand, double kerning) {
    DrawSetTextKerning(wand, kerning);
}

static inline void hokusai_draw_set_text_antialiasing(DrawingWand *wand, MagickBooleanType text_antialias) {
    DrawSetTextAntialias(wand, text_antialias);
}

// MARK: - Text Rendering - Color Configuration

static inline void hokusai_draw_set_fill_color(DrawingWand *wand, const PixelWand *fill_wand) {
    DrawSetFillColor(wand, fill_wand);
}

static inline void hokusai_draw_set_stroke_color(DrawingWand *wand, const PixelWand *stroke_wand) {
    DrawSetStrokeColor(wand, stroke_wand);
}

static inline void hokusai_draw_set_stroke_width(DrawingWand *wand, double stroke_width) {
    DrawSetStrokeWidth(wand, stroke_width);
}

static inline void hokusai_draw_set_fill_opacity(DrawingWand *wand, double opacity) {
    DrawSetFillOpacity(wand, opacity);
}

static inline void hokusai_draw_set_stroke_opacity(DrawingWand *wand, double opacity) {
    DrawSetStrokeOpacity(wand, opacity);
}

// MARK: - Text Rendering - Alignment/Gravity

static inline void hokusai_draw_set_gravity(DrawingWand *wand, GravityType gravity) {
    DrawSetGravity(wand, gravity);
}

static inline void hokusai_draw_set_text_alignment(DrawingWand *wand, AlignType alignment) {
    DrawSetTextAlignment(wand, alignment);
}

// MARK: - Text Rendering - Drawing

static inline MagickBooleanType hokusai_annotate_image(
    MagickWand *wand,
    DrawingWand *drawing_wand,
    double x,
    double y,
    double angle,
    const char *text
) {
    return MagickAnnotateImage(wand, drawing_wand, x, y, angle, text);
}

static inline MagickBooleanType hokusai_draw_image(MagickWand *wand, DrawingWand *drawing_wand) {
    return MagickDrawImage(wand, drawing_wand);
}

// MARK: - Pixel Configuration

static inline void hokusai_pixel_set_color(PixelWand *wand, const char *color) {
    PixelSetColor(wand, color);
}

static inline void hokusai_pixel_set_red(PixelWand *wand, double red) {
    PixelSetRed(wand, red);
}

static inline void hokusai_pixel_set_green(PixelWand *wand, double green) {
    PixelSetGreen(wand, green);
}

static inline void hokusai_pixel_set_blue(PixelWand *wand, double blue) {
    PixelSetBlue(wand, blue);
}

static inline void hokusai_pixel_set_alpha(PixelWand *wand, double alpha) {
    PixelSetAlpha(wand, alpha);
}

// MARK: - Error Handling

static inline char* hokusai_get_exception(MagickWand *wand, ExceptionType *severity) {
    return MagickGetException(wand, severity);
}

static inline MagickBooleanType hokusai_clear_exception(MagickWand *wand) {
    return MagickClearException(wand);
}

// MARK: - Version Info

static inline const char* hokusai_get_version(size_t *version) {
    return MagickGetVersion(version);
}

#endif /* CIMAGEMAGICK_SHIM_H */
