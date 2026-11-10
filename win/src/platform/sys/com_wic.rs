#![allow(non_snake_case, non_camel_case_types, dead_code)]

use core::ffi::c_void;

pub type HRESULT = i32;

pub const S_OK: HRESULT = 0;
pub const S_FALSE: HRESULT = 1;
pub const RPC_E_CHANGED_MODE: HRESULT = 0x8001_0106u32 as i32;

pub const COINIT_MULTITHREADED: u32 = 0x0;
pub const COINIT_APARTMENTTHREADED: u32 = 0x2;
pub const COINIT_DISABLE_OLE1DDE: u32 = 0x4;
pub const CLSCTX_INPROC_SERVER: u32 = 0x1;

pub const STREAM_SEEK_SET: u32 = 0;
pub const STREAM_SEEK_CUR: u32 = 1;
pub const STREAM_SEEK_END: u32 = 2;

pub const WIC_DECODE_METADATA_CACHE_ON_DEMAND: u32 = 0x0;
pub const WIC_BITMAP_DITHER_TYPE_NONE: u32 = 0x0;
pub const WIC_BITMAP_PALETTE_TYPE_MEDIAN_CUT: u32 = 0x1;
pub const WIC_BITMAP_INTERPOLATION_MODE_LINEAR: u32 = 0x1;
pub const WIC_BITMAP_INTERPOLATION_MODE_CUBIC: u32 = 0x2;
pub const WIC_BITMAP_INTERPOLATION_MODE_FANT: u32 = 0x3;
pub const WIC_BITMAP_ENCODER_NO_CACHE: u32 = 0x2;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GUID {
    pub data1: u32,
    pub data2: u16,
    pub data3: u16,
    pub data4: [u8; 8],
}

impl GUID {
    pub const fn new(data1: u32, data2: u16, data3: u16, data4: [u8; 8]) -> Self {
        Self { data1, data2, data3, data4 }
    }
}

pub const CLSID_WIC_IMAGING_FACTORY: GUID =
    GUID::new(0xcacaf262, 0x9370, 0x4615, [0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a]);
pub const IID_IWIC_IMAGING_FACTORY: GUID =
    GUID::new(0xec5ec8a9, 0xc395, 0x4314, [0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70]);
pub const GUID_CONTAINER_FORMAT_PNG: GUID =
    GUID::new(0x1b7cfaf4, 0x713f, 0x473c, [0xbb, 0xcd, 0x61, 0x37, 0x42, 0x5f, 0xae, 0xaf]);
pub const GUID_WIC_PIXEL_FORMAT_32BPP_BGRA: GUID =
    GUID::new(0x6fddc324, 0x4e03, 0x4bfe, [0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0f]);
pub const GUID_WIC_PIXEL_FORMAT_32BPP_PBGRA: GUID =
    GUID::new(0x6fddc324, 0x4e03, 0x4bfe, [0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10]);

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WICRect {
    pub X: i32,
    pub Y: i32,
    pub Width: i32,
    pub Height: i32,
}

#[repr(C)]
pub struct IUnknownVtbl {
    pub QueryInterface:
        unsafe extern "system" fn(this: *mut c_void, riid: *const GUID, ppv: *mut *mut c_void) -> HRESULT,
    pub AddRef: unsafe extern "system" fn(this: *mut c_void) -> u32,
    pub Release: unsafe extern "system" fn(this: *mut c_void) -> u32,
}

#[repr(C)]
pub struct IStream {
    pub lpVtbl: *const IStreamVtbl,
}

#[repr(C)]
pub struct IStreamVtbl {
    pub base: IUnknownVtbl,
    pub Read:
        unsafe extern "system" fn(this: *mut IStream, pv: *mut c_void, cb: u32, pcbRead: *mut u32) -> HRESULT,
    pub Write:
        unsafe extern "system" fn(this: *mut IStream, pv: *const c_void, cb: u32, pcbWritten: *mut u32) -> HRESULT,
    pub Seek:
        unsafe extern "system" fn(this: *mut IStream, dlibMove: i64, dwOrigin: u32, plibNewPosition: *mut u64) -> HRESULT,
    pub SetSize: *const c_void,
    pub CopyTo: *const c_void,
    pub Commit: *const c_void,
    pub Revert: *const c_void,
    pub LockRegion: *const c_void,
    pub UnlockRegion: *const c_void,
    pub Stat: *const c_void,
    pub Clone: *const c_void,
}

#[repr(C)]
pub struct IWICStream {
    pub lpVtbl: *const IWICStreamVtbl,
}

#[repr(C)]
pub struct IWICStreamVtbl {
    pub stream: IStreamVtbl,
    pub InitializeFromIStream: *const c_void,
    pub InitializeFromFilename: *const c_void,
    pub InitializeFromMemory:
        unsafe extern "system" fn(this: *mut IWICStream, pbBuffer: *const u8, cbBufferSize: u32) -> HRESULT,
    pub InitializeFromIStreamRegion: *const c_void,
}

#[repr(C)]
pub struct IWICBitmapSource {
    pub lpVtbl: *const IWICBitmapSourceVtbl,
}

#[repr(C)]
pub struct IWICBitmapSourceVtbl {
    pub base: IUnknownVtbl,
    pub GetSize:
        unsafe extern "system" fn(this: *mut IWICBitmapSource, puiWidth: *mut u32, puiHeight: *mut u32) -> HRESULT,
    pub GetPixelFormat:
        unsafe extern "system" fn(this: *mut IWICBitmapSource, pPixelFormat: *mut GUID) -> HRESULT,
    pub GetResolution: *const c_void,
    pub CopyPalette: *const c_void,
    pub CopyPixels: unsafe extern "system" fn(
        this: *mut IWICBitmapSource,
        prc: *const WICRect,
        cbStride: u32,
        cbBufferSize: u32,
        pbBuffer: *mut u8,
    ) -> HRESULT,
}

#[repr(C)]
pub struct IWICBitmapFrameDecode {
    pub lpVtbl: *const IWICBitmapFrameDecodeVtbl,
}

#[repr(C)]
pub struct IWICBitmapFrameDecodeVtbl {
    pub source: IWICBitmapSourceVtbl,
    pub GetMetadataQueryReader: *const c_void,
    pub GetColorContexts: *const c_void,
    pub GetThumbnail: *const c_void,
}

#[repr(C)]
pub struct IWICBitmapDecoder {
    pub lpVtbl: *const IWICBitmapDecoderVtbl,
}

#[repr(C)]
pub struct IWICBitmapDecoderVtbl {
    pub base: IUnknownVtbl,
    pub QueryCapability: *const c_void,
    pub Initialize: *const c_void,
    pub GetContainerFormat: *const c_void,
    pub GetDecoderInfo: *const c_void,
    pub CopyPalette: *const c_void,
    pub GetMetadataQueryReader: *const c_void,
    pub GetPreview: *const c_void,
    pub GetColorContexts: *const c_void,
    pub GetThumbnail: *const c_void,
    pub GetFrameCount:
        unsafe extern "system" fn(this: *mut IWICBitmapDecoder, pCount: *mut u32) -> HRESULT,
    pub GetFrame: unsafe extern "system" fn(
        this: *mut IWICBitmapDecoder,
        index: u32,
        ppIBitmapFrame: *mut *mut IWICBitmapFrameDecode,
    ) -> HRESULT,
}

#[repr(C)]
pub struct IWICFormatConverter {
    pub lpVtbl: *const IWICFormatConverterVtbl,
}

#[repr(C)]
pub struct IWICFormatConverterVtbl {
    pub source: IWICBitmapSourceVtbl,
    pub Initialize: unsafe extern "system" fn(
        this: *mut IWICFormatConverter,
        pISource: *mut IWICBitmapSource,
        dstFormat: *const GUID,
        dither: u32,
        pIPalette: *mut c_void,
        alphaThresholdPercent: f64,
        paletteTranslate: u32,
    ) -> HRESULT,
    pub CanConvert: *const c_void,
}

#[repr(C)]
pub struct IWICBitmapScaler {
    pub lpVtbl: *const IWICBitmapScalerVtbl,
}

#[repr(C)]
pub struct IWICBitmapScalerVtbl {
    pub source: IWICBitmapSourceVtbl,
    pub Initialize: unsafe extern "system" fn(
        this: *mut IWICBitmapScaler,
        pISource: *mut IWICBitmapSource,
        uiWidth: u32,
        uiHeight: u32,
        mode: u32,
    ) -> HRESULT,
}

#[repr(C)]
pub struct IWICBitmapFrameEncode {
    pub lpVtbl: *const IWICBitmapFrameEncodeVtbl,
}

#[repr(C)]
pub struct IWICBitmapFrameEncodeVtbl {
    pub base: IUnknownVtbl,
    pub Initialize:
        unsafe extern "system" fn(this: *mut IWICBitmapFrameEncode, pIEncoderOptions: *mut c_void) -> HRESULT,
    pub SetSize:
        unsafe extern "system" fn(this: *mut IWICBitmapFrameEncode, uiWidth: u32, uiHeight: u32) -> HRESULT,
    pub SetResolution: *const c_void,
    pub SetPixelFormat:
        unsafe extern "system" fn(this: *mut IWICBitmapFrameEncode, pPixelFormat: *mut GUID) -> HRESULT,
    pub SetColorContexts: *const c_void,
    pub SetPalette: *const c_void,
    pub SetThumbnail: *const c_void,
    pub WritePixels: unsafe extern "system" fn(
        this: *mut IWICBitmapFrameEncode,
        lineCount: u32,
        cbStride: u32,
        cbBufferSize: u32,
        pbPixels: *const u8,
    ) -> HRESULT,
    pub WriteSource: *const c_void,
    pub Commit: unsafe extern "system" fn(this: *mut IWICBitmapFrameEncode) -> HRESULT,
    pub GetMetadataQueryWriter: *const c_void,
}

#[repr(C)]
pub struct IWICBitmapEncoder {
    pub lpVtbl: *const IWICBitmapEncoderVtbl,
}

#[repr(C)]
pub struct IWICBitmapEncoderVtbl {
    pub base: IUnknownVtbl,
    pub Initialize:
        unsafe extern "system" fn(this: *mut IWICBitmapEncoder, pIStream: *mut IStream, cacheOption: u32) -> HRESULT,
    pub GetContainerFormat: *const c_void,
    pub GetEncoderInfo: *const c_void,
    pub SetColorContexts: *const c_void,
    pub SetPalette: *const c_void,
    pub SetThumbnail: *const c_void,
    pub SetPreview: *const c_void,
    pub CreateNewFrame: unsafe extern "system" fn(
        this: *mut IWICBitmapEncoder,
        ppIFrameEncode: *mut *mut IWICBitmapFrameEncode,
        ppIEncoderOptions: *mut *mut c_void,
    ) -> HRESULT,
    pub Commit: unsafe extern "system" fn(this: *mut IWICBitmapEncoder) -> HRESULT,
    pub GetMetadataQueryWriter: *const c_void,
}

#[repr(C)]
pub struct IWICImagingFactory {
    pub lpVtbl: *const IWICImagingFactoryVtbl,
}

#[repr(C)]
pub struct IWICImagingFactoryVtbl {
    pub base: IUnknownVtbl,
    pub CreateDecoderFromFilename: *const c_void,
    pub CreateDecoderFromStream: unsafe extern "system" fn(
        this: *mut IWICImagingFactory,
        pIStream: *mut IStream,
        pguidVendor: *const GUID,
        metadataOptions: u32,
        ppIDecoder: *mut *mut IWICBitmapDecoder,
    ) -> HRESULT,
    pub CreateDecoderFromFileHandle: *const c_void,
    pub CreateComponentInfo: *const c_void,
    pub CreateDecoder: *const c_void,
    pub CreateEncoder: unsafe extern "system" fn(
        this: *mut IWICImagingFactory,
        guidContainerFormat: *const GUID,
        pguidVendor: *const GUID,
        ppIEncoder: *mut *mut IWICBitmapEncoder,
    ) -> HRESULT,
    pub CreatePalette: *const c_void,
    pub CreateFormatConverter: unsafe extern "system" fn(
        this: *mut IWICImagingFactory,
        ppIFormatConverter: *mut *mut IWICFormatConverter,
    ) -> HRESULT,
    pub CreateBitmapScaler: unsafe extern "system" fn(
        this: *mut IWICImagingFactory,
        ppIBitmapScaler: *mut *mut IWICBitmapScaler,
    ) -> HRESULT,
    pub CreateBitmapClipper: *const c_void,
    pub CreateBitmapFlipRotator: *const c_void,
    pub CreateStream:
        unsafe extern "system" fn(this: *mut IWICImagingFactory, ppIWICStream: *mut *mut IWICStream) -> HRESULT,
}

/// Safe RAII wrapper for any COM interface pointer starting with `IUnknownVtbl`.
pub struct ComPtr<T> {
    ptr: *mut T,
}

impl<T> ComPtr<T> {
    pub unsafe fn from_raw(ptr: *mut T) -> Option<Self> {
        if ptr.is_null() { None } else { Some(Self { ptr }) }
    }

    pub fn as_ptr(&self) -> *mut T {
        self.ptr
    }
}

impl<T> Drop for ComPtr<T> {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe {
                let vtbl_ptr = *(self.ptr as *const *const IUnknownVtbl);
                ((*vtbl_ptr).Release)(self.ptr as *mut c_void);
            }
        }
    }
}

#[link(name = "ole32")]
extern "system" {
    pub fn CoInitializeEx(pvReserved: *const c_void, dwCoInit: u32) -> HRESULT;
    pub fn CoUninitialize();
    pub fn CoCreateInstance(
        rclsid: *const GUID,
        pUnkOuter: *mut c_void,
        dwClsContext: u32,
        riid: *const GUID,
        ppv: *mut *mut c_void,
    ) -> HRESULT;
    pub fn CreateStreamOnHGlobal(
        hGlobal: *mut c_void,
        fDeleteOnRelease: i32,
        ppstm: *mut *mut IStream,
    ) -> HRESULT;
}
