import Foundation
import CVips

extension MetadataPolicy {
    /// Lowers this policy for one image: the `VipsForeignKeep` set to hand the
    /// saver, and an image whose header is adjusted for the parts `keep`
    /// cannot express.
    ///
    /// Families map straight to native `keep` flags. Orientation and density
    /// are header fields, so they are handled on a private copy of the image
    /// (pixels are shared, never changed):
    ///
    /// - Orientation is stored inside EXIF. Removing EXIF but keeping
    ///   orientation therefore keeps a minimal EXIF block: every other EXIF
    ///   field is dropped from the copy and libvips rebuilds the block from
    ///   what remains.
    /// - Removing orientation deletes the tag without touching pixels.
    /// - Savers always record a resolution, so removing density resets it to
    ///   libvips' default of one pixel per millimetre (and drops the EXIF
    ///   resolution fields savers would otherwise read it from). A JPEG with no
    ///   EXIF block then gets the JFIF default of 72 DPI from the encoder.
    func lowered(for image: NativeImage, format: ImageFormat) throws -> (image: NativeImage, keep: Int32) {
        var keep: Int32 = 0
        if exif == .preserve { keep |= Int32(VIPS_FOREIGN_KEEP_EXIF.rawValue) }
        if xmp == .preserve { keep |= Int32(VIPS_FOREIGN_KEEP_XMP.rawValue) }
        if iptc == .preserve { keep |= Int32(VIPS_FOREIGN_KEEP_IPTC.rawValue) }
        if icc == .preserve { keep |= Int32(VIPS_FOREIGN_KEEP_ICC.rawValue) }
        if other == .preserve { keep |= Int32(VIPS_FOREIGN_KEEP_OTHER.rawValue) }

        let hasOrientation = image.hasMetadataField("orientation") || image.hasMetadataField("exif-ifd0-Orientation")
        let keepsMinimalExif = exif == .remove && orientation == .preserve && hasOrientation
        let dropsOrientation = orientation == .remove && hasOrientation
        let edits = keepsMinimalExif || dropsOrientation || density == .remove

        guard edits else { return (image, keep) }

        var result = try NativeImage.producing({ swift_vips_copy_private(image.pointer, $0) }, failure: { .nativeEncode(format.rawValue) })

        if dropsOrientation {
            result.removeMetadataFields(named: ["orientation", "exif-ifd0-Orientation"])
        }
        if keepsMinimalExif {
            result.removeMetadataFields(where: { $0.hasPrefix("exif-") && $0 != "exif-data" && $0 != "exif-ifd0-Orientation" })
            keep |= Int32(VIPS_FOREIGN_KEEP_EXIF.rawValue)
        } else if exif == .remove {
            // Savers can still read a resolution out of the raw block, so when
            // EXIF is removed outright the block goes too.
            result.removeMetadataFields(where: { $0.hasPrefix("exif-") })
        }
        if density == .remove {
            // Savers also read the resolution from EXIF fields, so those go too.
            result.removeMetadataFields(named: [
                "exif-ifd0-XResolution", "exif-ifd0-YResolution", "exif-ifd0-ResolutionUnit", "resolution-unit",
            ])
            result = try NativeImage.producing({ swift_vips_copy_with_resolution(result.pointer, $0, 1, 1) }, failure: { .nativeEncode(format.rawValue) })
        }
        return (result, keep)
    }
}

extension NativeImage {
    func hasMetadataField(_ name: String) -> Bool {
        swift_vips_image_has_field(pointer, name) != 0
    }

    /// Removes the named fields. Only call this on a private copy.
    fileprivate func removeMetadataFields(named names: [String]) {
        for name in names { _ = swift_vips_image_remove_field(pointer, name) }
    }

    /// Removes every field `predicate` accepts. Only call this on a private copy.
    fileprivate func removeMetadataFields(where predicate: (String) -> Bool) {
        guard let fields = swift_vips_image_get_fields(pointer) else { return }
        defer { swift_vips_g_strfreev(fields) }
        var index = 0
        while let field = fields[index] {
            let name = String(cString: field)
            if predicate(name) { _ = swift_vips_image_remove_field(pointer, name) }
            index += 1
        }
    }
}
