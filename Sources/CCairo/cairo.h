#include <cairo/cairo-pdf.h>

#if CAIRO_VERSION < CAIRO_VERSION_ENCODE(1, 16, 0)
#error "Hokusai requires Cairo 1.16 or later"
#endif
