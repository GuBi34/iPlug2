#include <Foundation/NSArchiver.h>

#include "IGraphicsMac.h"
#import "IGraphicsView.h"
#include "IControl.h"
#include "Log.h"

#include "swell-internal.h"

//TODO: why does this have to be here?
#define DEFAULT_PATH_MAC "~/Desktop"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

//https://gist.github.com/ccgus/3716936
SInt32 GetSystemVersion() {
  
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1090
  static dispatch_once_t once;
  static int SysVersionVal = 0x00;
  
  dispatch_once(&once, ^{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    
    NSString *prodVersion = [d objectForKey:@"ProductVersion"];
    
    if ([[prodVersion componentsSeparatedByString:@"."] count] < 3) {
      prodVersion = [prodVersion stringByAppendingString:@".0"];
    }
    
    NSString *junk = [prodVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
    
    char *e = nil;
    SysVersionVal = (int) strtoul([junk UTF8String], &e, 16);
    
  });
  
  return SysVersionVal;
#else
  SInt32 v;
  Gestalt(gestaltSystemVersion, &v);
  return v;
#endif
}

struct CocoaAutoReleasePool
{
  NSAutoreleasePool* mPool;

  CocoaAutoReleasePool()
  {
    mPool = [[NSAutoreleasePool alloc] init];
  }

  ~CocoaAutoReleasePool()
  {
    [mPool release];
  }
};

//#define IGRAPHICS_MAC_BLIT_BENCHMARK
//#define IGRAPHICS_MAC_OLD_IMAGE_DRAWING

#ifdef IGRAPHICS_MAC_BLIT_BENCHMARK
#include <sys/time.h>
static double gettm()
{
  struct timeval tm={0,};
  gettimeofday(&tm,NULL);
  return (double)tm.tv_sec + (double)tm.tv_usec/1000000;
}
#endif

#pragma mark -

IGraphicsMac::IGraphicsMac(IPlugBaseGraphics& plug, int w, int h, int fps)
  : IGRAPHICS_DRAW_CLASS(plug, w, h, fps)
  , mView(nullptr)
{
#if GRAPHICS_SCALING
  SetDisplayScale([[NSScreen mainScreen] backingScaleFactor]);
#endif
  NSApplicationLoad();
}

IGraphicsMac::~IGraphicsMac()
{
  CloseWindow();
}

void GetResourcePathFromBundle(const char* bundleID, const char* filename, const char* searchExt, WDL_String& fullPath)
{
  CocoaAutoReleasePool pool;

  const char* ext = filename+strlen(filename)-1;
  while (ext >= filename && *ext != '.') --ext;
  ++ext;

  bool isCorrectType = !stricmp(ext, searchExt);

  NSBundle* pBundle = [NSBundle bundleWithIdentifier:ToNSString(bundleID)];
  NSString* pFile = [[[NSString stringWithCString:filename] lastPathComponent] stringByDeletingPathExtension];
  
  if (isCorrectType && pBundle && pFile)
  {
    NSString* pPath = [pBundle pathForResource:pFile ofType:ToNSString(searchExt)];
    
    if (pPath)
    {
      fullPath.Set([pPath cString]);
      return;
    }
  }
}

void IGraphicsMac::OSLoadBitmap(const char* name, WDL_String& path)
{
  GetResourcePathFromBundle(GetBundleID(), name, "png", path);
}

void IGraphicsMac::DrawScreen(const IRECT& rect)
{
  if (!GetPlatformContext())
    return;
  
#ifdef IGRAPHICS_MAC_BLIT_BENCHMARK
  double tm=gettm();
#endif

  //TODO: this is silly, adapt api
  RenderAPIBitmap(GetPlatformContext());

#ifdef IGRAPHICS_MAC_BLIT_BENCHMARK
  printf("blit %fms\n",(gettm()-tm)*1000.0);
#endif
}

bool IGraphicsMac::MeasureIText(const IText& text, const char* str, IRECT& destRect)
{
  CocoaAutoReleasePool pool;

  return IGRAPHICS_DRAW_CLASS::MeasureIText(text, str, destRect);
}

void* IGraphicsMac::OpenWindow(void* pParent)
{
  TRACE;
  CloseWindow();
  mView = (IGRAPHICS_VIEW*) [[IGRAPHICS_VIEW alloc] initWithIGraphics: this];
  
  if (pParent) // Cocoa VST host.
  {
    [(NSView*) pParent addSubview: (IGRAPHICS_VIEW*) mView];
  }
  
  UpdateTooltips();
  
  return mView;
}

void IGraphicsMac::CloseWindow()
{
  if (mView)
  {
    IGRAPHICS_VIEW* view = (IGRAPHICS_VIEW*) mView;
    [view removeAllToolTips];
    [view killTimer];
    mView = nullptr;

    if (view->mGraphics)
    {
      SetPlatformContext(nullptr);
      view->mGraphics = nullptr;
      [view removeFromSuperview];   // Releases.
    }
  }
}

bool IGraphicsMac::WindowIsOpen()
{
  return mView;
}

void IGraphicsMac::Resize(int w, int h)
{
  if (w == Width() && h == Height()) return;

  IGraphics::Resize(w, h);

  if (mView)
  {
    NSSize size = { static_cast<CGFloat>(w), static_cast<CGFloat>(h) };
    [(IGRAPHICS_VIEW*) mView setFrameSize: size ];
  }
}

void IGraphicsMac::HideMouseCursor()
{
  if (!mCursorHidden)
  {
    if (CGDisplayHideCursor(CGMainDisplayID()) == CGDisplayNoErr) mCursorHidden = true;
    NSPoint mouse = [NSEvent mouseLocation];
    mHiddenMousePointX = mouse.x;
    mHiddenMousePointY = CGDisplayPixelsHigh(CGMainDisplayID())-mouse.y; //get current mouse position
  }
}

void IGraphicsMac::ShowMouseCursor()
{
  if (mCursorHidden)
  {
    CGPoint point; point.x = mHiddenMousePointX; point.y = mHiddenMousePointY;
    CGDisplayMoveCursorToPoint(CGMainDisplayID(), point);

    if (CGDisplayShowCursor(CGMainDisplayID()) == CGDisplayNoErr) mCursorHidden = false;
  }
}

int IGraphicsMac::ShowMessageBox(const char* text, const char* pCaption, int type)
{
  int result = 0;

  CFStringRef defaultButtonTitle = NULL;
  CFStringRef alternateButtonTitle = NULL;
  CFStringRef otherButtonTitle = NULL;

  CFStringRef alertMessage = CFStringCreateWithCStringNoCopy(NULL, text, 0, kCFAllocatorNull);
  CFStringRef alertHeader = CFStringCreateWithCStringNoCopy(NULL, pCaption, 0, kCFAllocatorNull);

  switch (type)
  {
    case MB_OKCANCEL:
      alternateButtonTitle = CFSTR("Cancel");
      break;
    case MB_YESNO:
      defaultButtonTitle = CFSTR("Yes");
      alternateButtonTitle = CFSTR("No");
      break;
    case MB_YESNOCANCEL:
      defaultButtonTitle = CFSTR("Yes");
      alternateButtonTitle = CFSTR("No");
      otherButtonTitle = CFSTR("Cancel");
      break;
  }

  CFOptionFlags response = 0;
  CFUserNotificationDisplayAlert(0, kCFUserNotificationNoteAlertLevel, NULL, NULL, NULL,
                                 alertHeader, alertMessage,
                                 defaultButtonTitle, alternateButtonTitle, otherButtonTitle,
                                 &response);

  CFRelease(alertMessage);
  CFRelease(alertHeader);

  switch (response) // TODO: check the return type, what about IDYES
  {
    case kCFUserNotificationDefaultResponse:
      result = IDOK;
      break;
    case kCFUserNotificationAlternateResponse:
      result = IDNO;
      break;
    case kCFUserNotificationOtherResponse:
      result = IDCANCEL;
      break;
  }

  return result;
}

void IGraphicsMac::ForceEndUserEdit()
{
  if (mView)
  {
    [(IGRAPHICS_VIEW*) mView endUserInput];
  }
}

void IGraphicsMac::UpdateTooltips()
{
  if (!(mView && TooltipsEnabled())) return;

  CocoaAutoReleasePool pool;
  
  [(IGRAPHICS_VIEW*) mView removeAllToolTips];
  
  IControl** ppControl = mControls.GetList();
  
  for (int i = 0, n = mControls.GetSize(); i < n; ++i, ++ppControl) 
  {
    IControl* pControl = *ppControl;
    const char* tooltip = pControl->GetTooltip();
    if (tooltip && !pControl->IsHidden()) 
    {
      IRECT pR = pControl->GetTargetRECT();
      if (!pControl->GetTargetRECT().Empty())
      {
        [(IGRAPHICS_VIEW*) mView registerToolTip: pR];
      }
    }
  }
}

const char* IGraphicsMac::GetGUIAPI()
{
  return "Cocoa";
}

void IGraphicsMac::HostPath(WDL_String& path)
{
  CocoaAutoReleasePool pool;
  NSBundle* pBundle = [NSBundle bundleWithIdentifier: ToNSString(GetBundleID())];
  
  if (pBundle)
  {
    NSString* pPath = [pBundle executablePath];
    if (pPath)
    {
      path.Set([pPath UTF8String]);
    }
  }
}

void IGraphicsMac::PluginPath(WDL_String& path)
{
  CocoaAutoReleasePool pool;
  NSBundle* pBundle = [NSBundle bundleWithIdentifier: ToNSString(GetBundleID())];
  
  if (pBundle)
  {
    NSString* pPath = [[pBundle bundlePath] stringByDeletingLastPathComponent];
    
    if (pPath)
    {
      path.Set([pPath UTF8String]);
      path.Append("/");
    }
  }
}

void IGraphicsMac::DesktopPath(WDL_String& path)
{
  NSArray* pPaths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
  NSString* pDesktopDirectory = [pPaths objectAtIndex:0];
  path.Set([pDesktopDirectory UTF8String]);
}

void IGraphicsMac::VST3PresetsPath(WDL_String& path, bool isSystem)
{
  NSArray* pPaths;
  if (isSystem)
    pPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES);
  else
    pPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
  
  NSString* pApplicationSupportDirectory = [pPaths objectAtIndex:0];
  path.SetFormatted(MAX_PATH, "%s/Audio/Presets/%s/%s/", [pApplicationSupportDirectory UTF8String], mPlug.GetMfrName(), mPlug.GetEffectName());
}

void IGraphicsMac::AppSupportPath(WDL_String& path, bool isSystem)
{
  NSArray *pPaths;
  
  if (isSystem)
    pPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSSystemDomainMask, YES);
  else
    pPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
  
  NSString *pApplicationSupportDirectory = [pPaths objectAtIndex:0];
  path.Set([pApplicationSupportDirectory UTF8String]);
}

void IGraphicsMac::SandboxSafeAppSupportPath(WDL_String& path)
{
  NSArray *pPaths = NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES);
  NSString *pUserMusicDirectory = [pPaths objectAtIndex:0];
  path.Set([pUserMusicDirectory UTF8String]);
}

// extensions = "txt wav" for example
void IGraphicsMac::PromptForFile(WDL_String& pFilename, EFileAction action, WDL_String* pDir, const char* extensions)
{
  if (!WindowIsOpen())
  {
    pFilename.Set("");
    return;
  }

  NSString* defaultFileName;
  NSString* defaultPath;
  NSArray* fileTypes = nil;

  if (pFilename.GetLength())
  {
    defaultFileName = [NSString stringWithCString:pFilename.Get() encoding:NSUTF8StringEncoding];
  }
  else
  {
    defaultFileName = [NSString stringWithCString:"" encoding:NSUTF8StringEncoding];
  }

  if (pDir->GetLength())
  {
    defaultPath = [NSString stringWithCString:pDir->Get() encoding:NSUTF8StringEncoding];
  }
  else
  {
    defaultPath = [NSString stringWithCString:DEFAULT_PATH_MAC encoding:NSUTF8StringEncoding];
    pDir->Set(DEFAULT_PATH_MAC);
  }

  pFilename.Set(""); // reset it

  //if (CSTR_NOT_EMPTY(extensions))
  fileTypes = [[NSString stringWithUTF8String:extensions] componentsSeparatedByString: @" "];

  if (action == kFileSave)
  {
    NSSavePanel* panelSave = [NSSavePanel savePanel];

    //[panelOpen setTitle:title];
    [panelSave setAllowedFileTypes: fileTypes];
    [panelSave setAllowsOtherFileTypes: NO];

    long result = [panelSave runModalForDirectory:defaultPath file:defaultFileName];

    if (result == NSOKButton)
    {
      NSString* fullPath = [ panelSave filename ] ;
      pFilename.Set( [fullPath UTF8String] );

      NSString* truncatedPath = [fullPath stringByDeletingLastPathComponent];

      if (truncatedPath)
      {
        pDir->Set([truncatedPath UTF8String]);
        pDir->Append("/");
      }
    }
  }
  else
  {
    NSOpenPanel* panelOpen = [NSOpenPanel openPanel];

    //[panelOpen setTitle:title];
    //[panelOpen setAllowsMultipleSelection:(allowmul?YES:NO)];
    [panelOpen setCanChooseFiles:YES];
    [panelOpen setCanChooseDirectories:NO];
    [panelOpen setResolvesAliases:YES];

    long result = [panelOpen runModalForDirectory:defaultPath file:defaultFileName types:fileTypes];

    if (result == NSOKButton)
    {
      NSString* fullPath = [ panelOpen filename ] ;
      pFilename.Set( [fullPath UTF8String] );

      NSString* truncatedPath = [fullPath stringByDeletingLastPathComponent];

      if (truncatedPath)
      {
        pDir->Set([truncatedPath UTF8String]);
        pDir->Append("/");
      }
    }
  }
}

bool IGraphicsMac::PromptForColor(IColor& color, const char* str)
{
  //TODO:
  return false;
}

IPopupMenu* IGraphicsMac::CreateIPopupMenu(IPopupMenu& menu, IRECT& textRect)
{
  ReleaseMouseCapture();

  if (mView)
  {
    NSRect areaRect = ToNSRect(this, textRect);
    return [(IGRAPHICS_VIEW*) mView createIPopupMenu: menu: areaRect];
  }
  else return 0;
}

void IGraphicsMac::CreateTextEntry(IControl* pControl, const IText& text, const IRECT& textRect, const char* str, IParam* pParam)
{
  if (mView)
  {
    NSRect areaRect = ToNSRect(this, textRect);
    [(IGRAPHICS_VIEW*) mView createTextEntry: pControl: pParam: text: str: areaRect];
  }
}

bool IGraphicsMac::OpenURL(const char* url, const char* msgWindowTitle, const char* confirmMsg, const char* errMsgOnFailure)
{
  #pragma REMINDER("Warning and error messages for OpenURL not implemented")
  NSURL* pNSURL = 0;
  if (strstr(url, "http"))
  {
    pNSURL = [NSURL URLWithString:ToNSString(url)];
  }
  else
  {
    pNSURL = [NSURL fileURLWithPath:ToNSString(url)];
  }
  if (pNSURL)
  {
    bool ok = ([[NSWorkspace sharedWorkspace] openURL:pNSURL]);
    // [pURL release];
    return ok;
  }
  return true;
}

void* IGraphicsMac::GetWindow()
{
  if (mView) return mView;
  else return 0;
}

// static
int IGraphicsMac::GetUserOSVersion()   // Returns a number like 0x1050 (10.5).
{
  SInt32 ver = GetSystemVersion();
  
  Trace(TRACELOC, "%x", ver);
  return (int) ver;
}

bool IGraphicsMac::GetTextFromClipboard(WDL_String& str)
{
  NSString* text = [[NSPasteboard generalPasteboard] stringForType: NSStringPboardType];
  
  if (text == nil)
  {
    str.Set("");
    return false;
  }
  else
  {
    str.Set([text UTF8String]);
    return true;
  }
}

//void IGraphicsMac::OSLoadFont(const char* name, const int size, WDL_String& fullPath)
//{
//  CocoaAutoReleasePool pool;
//
//  NSBundle * bundle = [NSBundle bundleWithIdentifier: ToNSString(GetBundleID())];
//
//  NSString * fontFilePath = [bundle resourcePath];
//  NSURL * fontsURL = [NSURL fileURLWithPath:fontFilePath];
//  if (fontsURL != nil)
//  {
//    OSStatus status;
//    FSRef fsRef;
//    CFURLGetFSRef((CFURLRef)fontsURL, &fsRef);
//    status = ATSFontActivateFromFileReference(&fsRef, kATSFontContextLocal, kATSFontFormatUnspecified, NULL, kATSOptionFlagsDefault, NULL);
//    if (status != noErr)
//    {
//      NSLog(@"Failed to activate local font path");
//    }
//  }

//  agg::font_mac * font = new agg::font_mac();
//
//  if (font->load_font(name, size))
//  {
//    return font;
//  }
//  else
//  {
//    delete font;
//  }

//  return;
//}
//
//bool IGraphicsMac::LoadSVGFile(const WDL_String & file, WDL_String & fileOut)
//{
//  NSBundle * bundle = [NSBundle bundleWithIdentifier: ToNSString(GetBundleID())];
//  NSString * svgFilePath = [[bundle resourcePath] stringByAppendingPathComponent:[NSString stringWithUTF8String:file.Get()]];
//
//  NSError * error = nil;
//  NSString * contents = [NSString stringWithContentsOfFile:svgFilePath encoding:NSUTF8StringEncoding error:&error];
//  if (contents != nil && error == nil)
//  {
//    fileOut.Set([contents UTF8String]);
//    return true;
//  }
//
//  return false;
//}

