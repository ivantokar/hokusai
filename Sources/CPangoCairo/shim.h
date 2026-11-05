#ifndef CPANGOCAIRO_HOKUSAI_H
#define CPANGOCAIRO_HOKUSAI_H

#include <pango/pangocairo.h>
#include <cairo-pdf.h>
#include <stdlib.h>
#include <string.h>

#if CAIRO_VERSION < CAIRO_VERSION_ENCODE(1, 16, 0)
#error "HokusaiPDF requires Cairo 1.16 or later"
#endif

#if !PANGO_VERSION_CHECK(1, 44, 0)
#error "HokusaiPDF requires Pango 1.44 or later (line spacing factors)"
#endif

/*
 * HokusaiPDF's native surface: Cairo draws the page, Pango lays out and draws text. Text goes through
 * pango_cairo_show_layout on a PDF surface, so it is emitted as real glyph runs with a ToUnicode map
 * (selectable and searchable), not as outlines or pixels.
 *
 * The functions here keep every Pango and Cairo detail that needs a macro, a variadic call or a GError
 * on the C side, so the Swift renderer sees plain integers and doubles.
 */

/** @brief A growing byte buffer that receives the PDF Cairo writes. */
typedef struct {
    unsigned char *data;
    size_t length;
    size_t capacity;
    int failed;
} HokusaiPDFBuffer;

static inline cairo_status_t hokusai_pdf_write(void *closure, const unsigned char *data, unsigned int length) {
    HokusaiPDFBuffer *buffer = (HokusaiPDFBuffer *) closure;
    if (buffer->failed) {
        return CAIRO_STATUS_WRITE_ERROR;
    }
    if (buffer->length + length > buffer->capacity) {
        size_t capacity = buffer->capacity ? buffer->capacity : 65536;
        while (capacity < buffer->length + length) {
            capacity *= 2;
        }
        unsigned char *grown = (unsigned char *) realloc(buffer->data, capacity);
        if (grown == NULL) {
            buffer->failed = 1;
            return CAIRO_STATUS_NO_MEMORY;
        }
        buffer->data = grown;
        buffer->capacity = capacity;
    }
    memcpy(buffer->data + buffer->length, data, length);
    buffer->length += length;
    return CAIRO_STATUS_SUCCESS;
}

static inline cairo_surface_t *hokusai_pdf_surface_create(HokusaiPDFBuffer *buffer, double width, double height) {
    return cairo_pdf_surface_create_for_stream(hokusai_pdf_write, buffer, width, height);
}

static inline void hokusai_pdf_buffer_free(HokusaiPDFBuffer *buffer) {
    free(buffer->data);
    buffer->data = NULL;
    buffer->length = buffer->capacity = 0;
}

/** @brief Whether the linked Cairo has its PDF surface. */
static inline int hokusai_vector_pdf_available(void) {
#ifdef CAIRO_HAS_PDF_SURFACE
    return 1;
#else
    return 0;
#endif
}

static inline void hokusai_pdf_set_metadata(cairo_surface_t *surface, int key, const char *value) {
    cairo_pdf_surface_set_metadata(surface, (cairo_pdf_metadata_t) key, value);
}

/** @brief Straight 8-bit RGBA to Cairo's premultiplied native-endian ARGB32, into `destination` rows of `stride` bytes. */
static inline void hokusai_rgba_to_cairo(const unsigned char *source, unsigned char *destination, int width, int height, int stride) {
    for (int y = 0; y < height; y++) {
        const unsigned char *in = source + (size_t) y * width * 4;
        uint32_t *out = (uint32_t *) (destination + (size_t) y * stride);
        for (int x = 0; x < width; x++) {
            const unsigned int a = in[3];
            const unsigned int r = (in[0] * a + 127) / 255;
            const unsigned int g = (in[1] * a + 127) / 255;
            const unsigned int b = (in[2] * a + 127) / 255;
            out[x] = (a << 24) | (r << 16) | (g << 8) | b;
            in += 4;
        }
    }
}

/**
 * @brief Draw `text` with its top-left corner at (x, y), in the units of `cr` (points on a PDF surface).
 *
 * `width` < 0 means no wrapping. `align`: 0 leading, 1 centre, 2 trailing, 3 justified. `wrap`: 0 word,
 * 1 character, 2 word then character. `spacing` is a line-height factor. `weight` is 100...900.
 * Returns the height of the laid-out text through `height`, or -1 when markup is invalid.
 */
static inline int hokusai_draw_text(
    cairo_t *cr, const char *text, int markup, double x, double y, double width,
    const char *family, double size, int weight, int italic,
    double red, double green, double blue, double alpha,
    int align, int wrap, double spacing, double *height
) {
    if (markup) {
        GError *error = NULL;
        if (!pango_parse_markup(text, -1, 0, NULL, NULL, NULL, &error)) {
            if (error != NULL) {
                g_error_free(error);
            }
            return -1;
        }
    }
    PangoLayout *layout = pango_cairo_create_layout(cr);
    PangoFontDescription *description = pango_font_description_new();
    pango_font_description_set_family(description, family);
    pango_font_description_set_weight(description, (PangoWeight) weight);
    pango_font_description_set_style(description, italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
    pango_font_description_set_absolute_size(description, size * PANGO_SCALE);
    pango_layout_set_font_description(layout, description);
    pango_font_description_free(description);

    if (markup) {
        pango_layout_set_markup(layout, text, -1);
    } else {
        pango_layout_set_text(layout, text, -1);
    }
    if (width >= 0) {
        pango_layout_set_width(layout, (int) (width * PANGO_SCALE));
        pango_layout_set_wrap(layout, wrap == 1 ? PANGO_WRAP_CHAR : (wrap == 2 ? PANGO_WRAP_WORD_CHAR : PANGO_WRAP_WORD));
    }
    pango_layout_set_alignment(layout, align == 1 ? PANGO_ALIGN_CENTER : (align == 2 ? PANGO_ALIGN_RIGHT : PANGO_ALIGN_LEFT));
    pango_layout_set_justify(layout, align == 3);
    pango_layout_set_line_spacing(layout, (float) spacing);

    cairo_save(cr);
    cairo_set_source_rgba(cr, red, green, blue, alpha);
    cairo_move_to(cr, x, y);
    pango_cairo_update_layout(cr, layout);
    pango_cairo_show_layout(cr, layout);
    int layout_width = 0, layout_height = 0;
    pango_layout_get_pixel_size(layout, &layout_width, &layout_height);
    PangoRectangle logical;
    pango_layout_get_extents(layout, NULL, &logical);
    *height = (double) logical.height / PANGO_SCALE;
    cairo_restore(cr);
    g_object_unref(layout);
    return 0;
}

#endif
