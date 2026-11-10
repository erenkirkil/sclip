use core::ffi::c_void;
use core::ptr;

use crate::platform::sys::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, ComPtr, CreateStreamOnHGlobal, IStream,
    IWICBitmapDecoder, IWICBitmapEncoder, IWICBitmapFrameDecode, IWICBitmapFrameEncode,
    IWICBitmapScaler, IWICBitmapSource, IWICFormatConverter, IWICImagingFactory, IWICStream,
    BI_BITFIELDS, BI_RGB, CLSCTX_INPROC_SERVER, CLSID_WIC_IMAGING_FACTORY,
    COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE, GUID, GUID_CONTAINER_FORMAT_PNG,
    GUID_WIC_PIXEL_FORMAT_32BPP_BGRA, GUID_WIC_PIXEL_FORMAT_32BPP_PBGRA, IID_IWIC_IMAGING_FACTORY,
    LCS_SRGB, RPC_E_CHANGED_MODE, STREAM_SEEK_CUR, STREAM_SEEK_SET, S_FALSE, S_OK, TRUE,
    WIC_BITMAP_DITHER_TYPE_NONE, WIC_BITMAP_ENCODER_NO_CACHE, WIC_BITMAP_INTERPOLATION_MODE_FANT,
    WIC_BITMAP_INTERPOLATION_MODE_LINEAR, WIC_BITMAP_PALETTE_TYPE_MEDIAN_CUT,
    WIC_DECODE_METADATA_CACHE_ON_DEMAND,
};

struct ComInitGuard(bool);

impl ComInitGuard {
    fn new() -> Option<Self> {
        let flags = COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE;
        match unsafe { CoInitializeEx(ptr::null(), flags) } {
            S_OK | S_FALSE => Some(Self(true)),
            RPC_E_CHANGED_MODE => Some(Self(false)),
            _ => None,
        }
    }
}

impl Drop for ComInitGuard {
    fn drop(&mut self) {
        if self.0 {
            unsafe { CoUninitialize() };
        }
    }
}

fn create_wic_factory() -> Option<ComPtr<IWICImagingFactory>> {
    let mut raw: *mut c_void = ptr::null_mut();
    let hr = unsafe {
        CoCreateInstance(
            &CLSID_WIC_IMAGING_FACTORY,
            ptr::null_mut(),
            CLSCTX_INPROC_SERVER,
            &IID_IWIC_IMAGING_FACTORY,
            &mut raw,
        )
    };
    if hr < 0 { None } else { unsafe { ComPtr::from_raw(raw as *mut IWICImagingFactory) } }
}

/// Converts `CF_DIB` or `CF_DIBV5` bytes into PNG bytes while preserving alpha transparency (`B-8.3.9`).
pub fn dib_to_png(dib: &[u8], _is_v5: bool) -> Option<Vec<u8>> {
    let (width, height, bgra) = parse_dib_to_bgra(dib)?;
    let _com = ComInitGuard::new()?;
    let factory = create_wic_factory()?;
    let out = encode_bgra_to_png(&factory, width, height, &bgra);
    drop(factory);
    out
}

/// Converts PNG (or any WIC-decodable image) bytes into a 32-bit `CF_DIBV5` payload with alpha (`B-8.9.4`).
pub fn png_to_dibv5(png: &[u8]) -> Option<Vec<u8>> {
    let _com = ComInitGuard::new()?;
    let factory = create_wic_factory()?;
    let decoded = decode_image_with_wic(&factory, png, &GUID_WIC_PIXEL_FORMAT_32BPP_BGRA, None);
    drop(factory);
    let (width, height, top_down_bgra) = decoded?;
    if width == 0 || height == 0 {
        return None;
    }
    let row_bytes = (width as usize).checked_mul(4)?;
    let image_size = row_bytes.checked_mul(height as usize)?;
    let header_size = 124usize;
    let mut out = vec![0u8; header_size + image_size];

    out[0..4].copy_from_slice(&(header_size as u32).to_le_bytes());
    out[4..8].copy_from_slice(&(width as i32).to_le_bytes());
    out[8..12].copy_from_slice(&(height as i32).to_le_bytes());
    out[12..14].copy_from_slice(&1u16.to_le_bytes());
    out[14..16].copy_from_slice(&32u16.to_le_bytes());
    out[16..20].copy_from_slice(&BI_BITFIELDS.to_le_bytes());
    out[20..24].copy_from_slice(&(image_size as u32).to_le_bytes());
    out[24..28].copy_from_slice(&3780i32.to_le_bytes());
    out[28..32].copy_from_slice(&3780i32.to_le_bytes());
    out[40..44].copy_from_slice(&0x00FF_0000u32.to_le_bytes());
    out[44..48].copy_from_slice(&0x0000_FF00u32.to_le_bytes());
    out[48..52].copy_from_slice(&0x0000_00FFu32.to_le_bytes());
    out[52..56].copy_from_slice(&0xFF00_0000u32.to_le_bytes());
    out[56..60].copy_from_slice(&LCS_SRGB.to_le_bytes());

    for y in 0..(height as usize) {
        let src_row = (height as usize - 1 - y) * row_bytes;
        let dst_row = header_size + y * row_bytes;
        out[dst_row..dst_row + row_bytes]
            .copy_from_slice(&top_down_bgra[src_row..src_row + row_bytes]);
    }
    Some(out)
}

/// Decodes and scales an image (PNG/JPEG/GIF/WebP) to fit within `max_pixel_size` in premultiplied BGRA (`B-8.6.10`).
pub fn decode_thumbnail_bgra(
    image_bytes: &[u8],
    max_pixel_size: u32,
) -> Option<(u32, u32, Vec<u8>)> {
    if image_bytes.is_empty() || max_pixel_size == 0 {
        return None;
    }
    let _com = ComInitGuard::new()?;
    let factory = create_wic_factory()?;
    let out = decode_image_with_wic(
        &factory,
        image_bytes,
        &GUID_WIC_PIXEL_FORMAT_32BPP_PBGRA,
        Some(max_pixel_size),
    );
    drop(factory);
    out
}

fn decode_image_with_wic(
    factory: &ComPtr<IWICImagingFactory>,
    image_bytes: &[u8],
    target_format: &GUID,
    max_pixel_size: Option<u32>,
) -> Option<(u32, u32, Vec<u8>)> {
    let len = u32::try_from(image_bytes.len()).ok()?;
    let f_vtbl = unsafe { &*(*factory.as_ptr()).lpVtbl };

    let mut raw_stream: *mut IWICStream = ptr::null_mut();
    if unsafe { (f_vtbl.CreateStream)(factory.as_ptr(), &mut raw_stream) } < 0 {
        return None;
    }
    let stream = unsafe { ComPtr::from_raw(raw_stream) }?;
    let s_vtbl = unsafe { &*(*stream.as_ptr()).lpVtbl };
    if unsafe { (s_vtbl.InitializeFromMemory)(stream.as_ptr(), image_bytes.as_ptr(), len) } < 0 {
        return None;
    }

    let mut raw_dec: *mut IWICBitmapDecoder = ptr::null_mut();
    let hr_dec = unsafe {
        (f_vtbl.CreateDecoderFromStream)(
            factory.as_ptr(),
            stream.as_ptr() as *mut IStream,
            ptr::null(),
            WIC_DECODE_METADATA_CACHE_ON_DEMAND,
            &mut raw_dec,
        )
    };
    if hr_dec < 0 {
        return None;
    }
    let decoder = unsafe { ComPtr::from_raw(raw_dec) }?;
    let d_vtbl = unsafe { &*(*decoder.as_ptr()).lpVtbl };

    let mut raw_frame: *mut IWICBitmapFrameDecode = ptr::null_mut();
    if unsafe { (d_vtbl.GetFrame)(decoder.as_ptr(), 0, &mut raw_frame) } < 0 {
        return None;
    }
    let frame = unsafe { ComPtr::from_raw(raw_frame) }?;
    let fr_vtbl = unsafe { &*(*frame.as_ptr()).lpVtbl };

    let (mut orig_w, mut orig_h) = (0u32, 0u32);
    if unsafe { (fr_vtbl.source.GetSize)(frame.as_ptr() as *mut IWICBitmapSource, &mut orig_w, &mut orig_h) } < 0
        || orig_w == 0
        || orig_h == 0
    {
        return None;
    }

    let mut raw_conv: *mut IWICFormatConverter = ptr::null_mut();
    if unsafe { (f_vtbl.CreateFormatConverter)(factory.as_ptr(), &mut raw_conv) } < 0 {
        return None;
    }
    let converter = unsafe { ComPtr::from_raw(raw_conv) }?;
    let c_vtbl = unsafe { &*(*converter.as_ptr()).lpVtbl };
    let hr_conv = unsafe {
        (c_vtbl.Initialize)(
            converter.as_ptr(),
            frame.as_ptr() as *mut IWICBitmapSource,
            target_format,
            WIC_BITMAP_DITHER_TYPE_NONE,
            ptr::null_mut(),
            0.0,
            WIC_BITMAP_PALETTE_TYPE_MEDIAN_CUT,
        )
    };
    if hr_conv < 0 {
        return None;
    }

    let (out_w, out_h) = match max_pixel_size {
        Some(m) if orig_w > m || orig_h > m => {
            if orig_w >= orig_h {
                (m, ((orig_h as u64 * m as u64 + (orig_w as u64 / 2)) / orig_w as u64).max(1) as u32)
            } else {
                (((orig_w as u64 * m as u64 + (orig_h as u64 / 2)) / orig_h as u64).max(1) as u32, m)
            }
        }
        _ => (orig_w, orig_h),
    };

    let stride = out_w.checked_mul(4)?;
    let total_bytes = stride.checked_mul(out_h)?;
    let mut pixels = vec![0u8; total_bytes as usize];

    if max_pixel_size.is_some() {
        let mut raw_scaler: *mut IWICBitmapScaler = ptr::null_mut();
        if unsafe { (f_vtbl.CreateBitmapScaler)(factory.as_ptr(), &mut raw_scaler) } < 0 {
            return None;
        }
        let scaler = unsafe { ComPtr::from_raw(raw_scaler) }?;
        let sc_vtbl = unsafe { &*(*scaler.as_ptr()).lpVtbl };
        let conv_src = converter.as_ptr() as *mut IWICBitmapSource;
        let mut hr = unsafe {
            (sc_vtbl.Initialize)(scaler.as_ptr(), conv_src, out_w, out_h, WIC_BITMAP_INTERPOLATION_MODE_FANT)
        };
        if hr < 0 {
            hr = unsafe {
                (sc_vtbl.Initialize)(scaler.as_ptr(), conv_src, out_w, out_h, WIC_BITMAP_INTERPOLATION_MODE_LINEAR)
            };
        }
        let sc_src = scaler.as_ptr() as *mut IWICBitmapSource;
        if hr < 0 || unsafe { (sc_vtbl.source.CopyPixels)(sc_src, ptr::null(), stride, total_bytes, pixels.as_mut_ptr()) } < 0 {
            return None;
        }
    } else {
        let conv_src = converter.as_ptr() as *mut IWICBitmapSource;
        if unsafe { (c_vtbl.source.CopyPixels)(conv_src, ptr::null(), stride, total_bytes, pixels.as_mut_ptr()) } < 0 {
            return None;
        }
    }

    Some((out_w, out_h, pixels))
}

fn encode_bgra_to_png(
    factory: &ComPtr<IWICImagingFactory>,
    width: u32,
    height: u32,
    bgra: &[u8],
) -> Option<Vec<u8>> {
    let stride = width.checked_mul(4)?;
    let expected_len = stride.checked_mul(height)? as usize;
    if bgra.len() < expected_len {
        return None;
    }
    let f_vtbl = unsafe { &*(*factory.as_ptr()).lpVtbl };

    let mut raw_istream: *mut IStream = ptr::null_mut();
    if unsafe { CreateStreamOnHGlobal(ptr::null_mut(), TRUE, &mut raw_istream) } < 0 {
        return None;
    }
    let istream = unsafe { ComPtr::from_raw(raw_istream) }?;

    let mut raw_enc: *mut IWICBitmapEncoder = ptr::null_mut();
    if unsafe { (f_vtbl.CreateEncoder)(factory.as_ptr(), &GUID_CONTAINER_FORMAT_PNG, ptr::null(), &mut raw_enc) } < 0 {
        return None;
    }
    let encoder = unsafe { ComPtr::from_raw(raw_enc) }?;
    let e_vtbl = unsafe { &*(*encoder.as_ptr()).lpVtbl };
    if unsafe { (e_vtbl.Initialize)(encoder.as_ptr(), istream.as_ptr(), WIC_BITMAP_ENCODER_NO_CACHE) } < 0 {
        return None;
    }

    let mut raw_frame: *mut IWICBitmapFrameEncode = ptr::null_mut();
    let mut raw_opts: *mut c_void = ptr::null_mut();
    if unsafe { (e_vtbl.CreateNewFrame)(encoder.as_ptr(), &mut raw_frame, &mut raw_opts) } < 0 {
        return None;
    }
    let _opts = unsafe { ComPtr::from_raw(raw_opts) };
    let frame = unsafe { ComPtr::from_raw(raw_frame) }?;
    let fr_vtbl = unsafe { &*(*frame.as_ptr()).lpVtbl };

    let mut pixel_fmt = GUID_WIC_PIXEL_FORMAT_32BPP_BGRA;
    if unsafe { (fr_vtbl.Initialize)(frame.as_ptr(), raw_opts) } < 0
        || unsafe { (fr_vtbl.SetSize)(frame.as_ptr(), width, height) } < 0
        || unsafe { (fr_vtbl.SetPixelFormat)(frame.as_ptr(), &mut pixel_fmt) } < 0
        || unsafe { (fr_vtbl.WritePixels)(frame.as_ptr(), height, stride, expected_len as u32, bgra.as_ptr()) } < 0
        || unsafe { (fr_vtbl.Commit)(frame.as_ptr()) } < 0
        || unsafe { (e_vtbl.Commit)(encoder.as_ptr()) } < 0
    {
        return None;
    }

    let is_vtbl = unsafe { &*(*istream.as_ptr()).lpVtbl };
    let mut written_len: u64 = 0;
    if unsafe { (is_vtbl.Seek)(istream.as_ptr(), 0, STREAM_SEEK_CUR, &mut written_len) } < 0 {
        return None;
    }
    let size = usize::try_from(written_len).ok()?;
    let mut dummy_pos: u64 = 0;
    if size == 0 || unsafe { (is_vtbl.Seek)(istream.as_ptr(), 0, STREAM_SEEK_SET, &mut dummy_pos) } < 0 {
        return None;
    }
    let mut out = vec![0u8; size];
    let mut bytes_read: u32 = 0;
    if unsafe { (is_vtbl.Read)(istream.as_ptr(), out.as_mut_ptr() as *mut c_void, size as u32, &mut bytes_read) } < 0
        || (bytes_read as usize) != size
    {
        return None;
    }
    Some(out)
}

fn read_u32_le(b: &[u8], off: usize) -> u32 {
    u32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]])
}

fn parse_dib_to_bgra(dib: &[u8]) -> Option<(u32, u32, Vec<u8>)> {
    if dib.len() < 40 {
        return None;
    }
    let header_size = read_u32_le(dib, 0) as usize;
    if header_size < 40 || dib.len() < header_size {
        return None;
    }
    let (width_i, height_i) = (read_u32_le(dib, 4) as i32, read_u32_le(dib, 8) as i32);
    let planes = u16::from_le_bytes([dib[12], dib[13]]);
    let bpp = u16::from_le_bytes([dib[14], dib[15]]);
    let (compression, clr_used) = (read_u32_le(dib, 16), read_u32_le(dib, 32) as usize);
    if width_i <= 0 || height_i == 0 || height_i == i32::MIN || planes != 1 {
        return None;
    }
    let (width, top_down, height) = (width_i as u32, height_i < 0, height_i.unsigned_abs());
    let (w, h) = (width as usize, height as usize);
    let out_len = w.checked_mul(h)?.checked_mul(4)?;
    let mut bgra = vec![0u8; out_len];

    if bpp == 32 && (compression == BI_RGB || compression == BI_BITFIELDS) {
        let (rm, gm, bm, am, off) = if compression == BI_BITFIELDS {
            if header_size >= 56 {
                let off = if dib.len() == header_size + 12 + out_len { header_size + 12 } else { header_size };
                (read_u32_le(dib, 40), read_u32_le(dib, 44), read_u32_le(dib, 48), read_u32_le(dib, 52), off)
            } else if dib.len() >= 52 {
                (read_u32_le(dib, 40), read_u32_le(dib, 44), read_u32_le(dib, 48), 0xFF00_0000, 52)
            } else {
                return None;
            }
        } else {
            (0x00FF_0000, 0x0000_FF00, 0x0000_00FF, 0xFF00_0000, header_size + clr_used * 4)
        };
        let src = dib.get(off..off.checked_add(out_len)?)?;
        let mut any_alpha = false;
        for y in 0..h {
            let (src_row, dst_row) = ((if top_down { y } else { h - 1 - y }) * w * 4, y * w * 4);
            for x in 0..w {
                let px = read_u32_le(src, src_row + x * 4);
                let a = if am != 0 { extract_channel(px, am) } else { 255 };
                any_alpha |= a != 0;
                let di = dst_row + x * 4;
                bgra[di..di + 4].copy_from_slice(&[extract_channel(px, bm), extract_channel(px, gm), extract_channel(px, rm), a]);
            }
        }
        if header_size == 40 && compression == BI_RGB && !any_alpha {
            bgra.iter_mut().skip(3).step_by(4).for_each(|a| *a = 255);
        }
        Some((width, height, bgra))
    } else if bpp == 24 && compression == BI_RGB {
        let src_stride = (w.checked_mul(3)? + 3) & !3;
        let off = header_size + clr_used * 4;
        let src = dib.get(off..off.checked_add(src_stride.checked_mul(h)?)?)?;
        for y in 0..h {
            let (src_row, dst_row) = ((if top_down { y } else { h - 1 - y }) * src_stride, y * w * 4);
            for x in 0..w {
                let (si, di) = (src_row + x * 3, dst_row + x * 4);
                bgra[di..di + 4].copy_from_slice(&[src[si], src[si + 1], src[si + 2], 255]);
            }
        }
        Some((width, height, bgra))
    } else {
        None
    }
}

fn extract_channel(pixel: u32, mask: u32) -> u8 {
    if mask == 0 {
        return 0;
    }
    let shift = mask.trailing_zeros();
    let (max_val, raw) = (mask >> shift, (pixel & mask) >> shift);
    if max_val == 0xFF { raw as u8 } else { ((raw as u64 * 255 + (max_val as u64 / 2)) / max_val as u64).min(255) as u8 }
}
