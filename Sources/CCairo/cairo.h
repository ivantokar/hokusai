#ifndef CCAIRO_HOKUSAI_PDF_H
#define CCAIRO_HOKUSAI_PDF_H

#include <cairo/cairo-pdf.h>
#include <stdlib.h>

#if CAIRO_VERSION < CAIRO_VERSION_ENCODE(1, 16, 0)
#error "Hokusai requires Cairo 1.16 or later"
#endif

/*
 * Hokusai's raster-PDF writer.
 *
 * This is the whole Cairo surface of the package: a small bridge that turns
 * already-prepared pixels into PDF pages. It knows nothing about libvips (the
 * raster arrives as a plain premultiplied ARGB32 buffer) and reports failures
 * as Cairo statuses, never through libvips' error log. Output goes to a write
 * callback, so memory, file, and future stream sinks share one path.
 */

/** @brief Whether the linked Cairo was built with its PDF surface. */
static inline int hokusai_cairo_pdf_available(void) {
#ifdef CAIRO_HAS_PDF_SURFACE
    return 1;
#else
    return 0;
#endif
}

/** @brief Bytes per row Cairo requires for an ARGB32 surface of `width` pixels, or -1. */
static inline int hokusai_cairo_argb32_stride(int width) {
    return cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, width);
}

/**
 * @brief Convert straight 8-bit RGBA pixels to Cairo's premultiplied ARGB32, in place.
 *
 * Colour channels are multiplied by alpha with rounding, then bytes are laid
 * out in the native 32-bit order (B, G, R, A in memory on little-endian
 * machines). Doing this over the single raster libvips materialised avoids a
 * second full-size buffer.
 */
static inline void hokusai_rgba_to_argb32_premultiplied(unsigned char *pixels, size_t pixel_count) {
    for (size_t index = 0; index < pixel_count; index++) {
        unsigned char *pixel = pixels + index * 4;
        const unsigned int alpha = pixel[3];
        const unsigned char red = (unsigned char) ((pixel[0] * alpha + 127) / 255);
        const unsigned char green = (unsigned char) ((pixel[1] * alpha + 127) / 255);
        const unsigned char blue = (unsigned char) ((pixel[2] * alpha + 127) / 255);
#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
        pixel[0] = (unsigned char) alpha;
        pixel[1] = red;
        pixel[2] = green;
        pixel[3] = blue;
#else
        pixel[0] = blue;
        pixel[1] = green;
        pixel[2] = red;
        pixel[3] = (unsigned char) alpha;
#endif
    }
}

/** @brief Cairo's description of a status code. Static storage; do not free. */
static inline const char *hokusai_cairo_status_string(int status) {
    return cairo_status_to_string((cairo_status_t) status);
}

/**
 * Receives PDF bytes. Return 0 to accept them; any other value aborts the
 * document with a write error (a full disk, or a cancelled evaluation).
 */
typedef int (*HokusaiPDFWrite)(void *context, const unsigned char *data, unsigned int length);

typedef struct {
    cairo_surface_t *surface;
    cairo_t *context;
    HokusaiPDFWrite write;
    void *write_context;
    int pages;
} HokusaiPDF;

#ifdef CAIRO_HAS_PDF_SURFACE

static cairo_status_t hokusai_pdf_stream_write(void *closure, const unsigned char *data, unsigned int length) {
    HokusaiPDF *document = (HokusaiPDF *) closure;
    return document->write(document->write_context, data, length) == 0 ? CAIRO_STATUS_SUCCESS : CAIRO_STATUS_WRITE_ERROR;
}

/**
 * @brief Start a PDF whose first page is `width` × `height` points.
 *
 * Optional document metadata (UTF-8, or NULL) is set before any page is
 * drawn. Returns NULL only when memory is exhausted; otherwise check
 * hokusai_pdf_status().
 */
static inline HokusaiPDF *hokusai_pdf_begin(
    HokusaiPDFWrite write, void *write_context, double width, double height,
    const char *title, const char *author, const char *subject, const char *keywords, const char *creator,
    const char *created, const char *modified
) {
    HokusaiPDF *document = (HokusaiPDF *) calloc(1, sizeof(HokusaiPDF));
    if (document == NULL) {
        return NULL;
    }
    document->write = write;
    document->write_context = write_context;
    document->surface = cairo_pdf_surface_create_for_stream(hokusai_pdf_stream_write, document, width, height);
    if (cairo_surface_status(document->surface) != CAIRO_STATUS_SUCCESS) {
        return document;
    }
    if (title) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_TITLE, title);
    if (author) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_AUTHOR, author);
    if (subject) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_SUBJECT, subject);
    if (keywords) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_KEYWORDS, keywords);
    if (creator) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_CREATOR, creator);
    if (created) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_CREATE_DATE, created);
    if (modified) cairo_pdf_surface_set_metadata(document->surface, CAIRO_PDF_METADATA_MOD_DATE, modified);
    document->context = cairo_create(document->surface);
    return document;
}

/** @brief The first failure Cairo recorded for this document, or 0. */
static inline int hokusai_pdf_status(HokusaiPDF *document) {
    if (document->surface == NULL) {
        return CAIRO_STATUS_NO_MEMORY;
    }
    cairo_status_t status = cairo_surface_status(document->surface);
    if (status == CAIRO_STATUS_SUCCESS && document->context != NULL) {
        status = cairo_status(document->context);
    }
    return (int) status;
}

/**
 * @brief Draw one page: an optional background fill, then the raster scaled
 * into the rectangle (x, y, w, h) in points.
 *
 * `pixels` is premultiplied native-endian ARGB32 with `stride` bytes per row.
 * The first page uses the size given to hokusai_pdf_begin(); later pages
 * resize the surface first.
 */
static inline int hokusai_pdf_add_page(
    HokusaiPDF *document, double page_width, double page_height,
    int has_background, double red, double green, double blue, double alpha,
    unsigned char *pixels, int width, int height, int stride,
    double x, double y, double w, double h
) {
    int status = hokusai_pdf_status(document);
    if (status != CAIRO_STATUS_SUCCESS) {
        return status;
    }
    if (document->pages > 0) {
        cairo_pdf_surface_set_size(document->surface, page_width, page_height);
    }
    cairo_surface_t *image = cairo_image_surface_create_for_data(pixels, CAIRO_FORMAT_ARGB32, width, height, stride);
    if (cairo_surface_status(image) != CAIRO_STATUS_SUCCESS) {
        status = (int) cairo_surface_status(image);
        cairo_surface_destroy(image);
        return status;
    }
    if (has_background) {
        cairo_set_source_rgba(document->context, red, green, blue, alpha);
        cairo_paint(document->context);
    }
    cairo_save(document->context);
    cairo_translate(document->context, x, y);
    cairo_scale(document->context, w / width, h / height);
    cairo_set_source_surface(document->context, image, 0, 0);
    cairo_paint(document->context);
    cairo_restore(document->context);
    cairo_show_page(document->context);
    cairo_surface_destroy(image);
    document->pages += 1;
    return hokusai_pdf_status(document);
}

/** @brief Finish the document, flushing all bytes through the write callback. Returns the final status. */
static inline int hokusai_pdf_finish(HokusaiPDF *document) {
    if (document->surface != NULL) {
        cairo_surface_finish(document->surface);
    }
    return hokusai_pdf_status(document);
}

#else

static inline HokusaiPDF *hokusai_pdf_begin(
    HokusaiPDFWrite write, void *write_context, double width, double height,
    const char *title, const char *author, const char *subject, const char *keywords, const char *creator,
    const char *created, const char *modified
) {
    return (HokusaiPDF *) calloc(1, sizeof(HokusaiPDF));
}

static inline int hokusai_pdf_status(HokusaiPDF *document) { return CAIRO_STATUS_INVALID_STATUS; }

static inline int hokusai_pdf_add_page(
    HokusaiPDF *document, double page_width, double page_height,
    int has_background, double red, double green, double blue, double alpha,
    unsigned char *pixels, int width, int height, int stride,
    double x, double y, double w, double h
) {
    return CAIRO_STATUS_INVALID_STATUS;
}

static inline int hokusai_pdf_finish(HokusaiPDF *document) { return CAIRO_STATUS_INVALID_STATUS; }

#endif

/** @brief Pages drawn so far. */
static inline int hokusai_pdf_page_count(const HokusaiPDF *document) {
    return document->pages;
}

/** @brief Release the document. Call after hokusai_pdf_finish(). */
static inline void hokusai_pdf_free(HokusaiPDF *document) {
#ifdef CAIRO_HAS_PDF_SURFACE
    if (document->context != NULL) cairo_destroy(document->context);
    if (document->surface != NULL) cairo_surface_destroy(document->surface);
#endif
    free(document);
}

#endif /* CCAIRO_HOKUSAI_PDF_H */
