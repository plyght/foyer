#import <Cocoa/Cocoa.h>
// Test-only adapter to macOS private CGVirtualDisplay. No physical display assumed.
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic) unsigned int vendorID, productID, serialNum;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic) NSString *name;
@property(nonatomic) dispatch_queue_t queue;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)w height:(unsigned int)h refreshRate:(double)hz;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)d;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)s;
@property(nonatomic,readonly) CGDirectDisplayID displayID;
@end
@interface DisplayDelegate : NSObject <NSApplicationDelegate>
@property CGVirtualDisplay *display;
@property NSWindow *window;
@property NSTextField *status;
@property NSWindow *marker;
@end
@implementation DisplayDelegate
- (void)update {
    self.status.stringValue=[NSString stringWithFormat:@"Virtual ID: %u   NSScreen count: %lu   %@",self.display.displayID,(unsigned long)NSScreen.screens.count,self.display?@"CONNECTED":@"DISCONNECTED"];
    NSLog(@"%@",self.status.stringValue);
}
- (void)plug:(id)s {
    if(self.display)return;
    Class dc=NSClassFromString(@"CGVirtualDisplayDescriptor"), vc=NSClassFromString(@"CGVirtualDisplay");
    if(!dc||!vc){self.status.stringValue=@"Unavailable: CGVirtualDisplay runtime classes absent";return;}
    CGVirtualDisplayDescriptor *d=[dc new];
    d.name=@"Alcove Synthetic Display";d.vendorID=0xF0F0;d.productID=0xA1C0;d.serialNum=4242;
    d.maxPixelsWide=1280;d.maxPixelsHigh=720;d.sizeInMillimeters=CGSizeMake(300,170);
    d.redPrimary=CGPointMake(.64,.33);d.greenPrimary=CGPointMake(.30,.60);d.bluePrimary=CGPointMake(.15,.06);d.whitePoint=CGPointMake(.3127,.3290);
    d.queue=dispatch_get_main_queue();
    self.display=[[vc alloc] initWithDescriptor:d];
    CGVirtualDisplaySettings *cfg=[NSClassFromString(@"CGVirtualDisplaySettings") new];
    cfg.hiDPI=0;
    cfg.modes=@[[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1280 height:720 refreshRate:60]];
    BOOL ok=[self.display applySettings:cfg];
    NSLog(@"applySettings=%d ID=%u",ok,self.display.displayID);
    [self performSelector:@selector(markerOnDisplay) withObject:nil afterDelay:1];
    [self performSelector:@selector(update) withObject:nil afterDelay:1];
}
- (void)markerOnDisplay {
    for(NSScreen *screen in NSScreen.screens){
        if([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue]!=self.display.displayID)continue;
        [self.marker close];
        self.marker=[[NSWindow alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO screen:screen];
        self.marker.releasedWhenClosed=NO;
        self.marker.backgroundColor=[NSColor colorWithRed:.93 green:.86 blue:.66 alpha:1];
        self.marker.ignoresMouseEvents=YES;
        NSTextField *label=[NSTextField labelWithString:@"ALCOVE SYNTHETIC DISPLAY • 1280 × 720 • 60 Hz"];
        label.frame=NSMakeRect(20,260,1240,100);label.alignment=NSTextAlignmentCenter;label.font=[NSFont systemFontOfSize:28 weight:NSFontWeightBold];
        [self.marker.contentView addSubview:label];[self.marker orderBack:nil];
    }
}
- (void)unplug:(id)s { [self.marker close];self.marker=nil;self.display=nil;[self performSelector:@selector(update) withObject:nil afterDelay:1]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(200,200,760,220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed=NO;
    self.window.title=@"Synthetic virtual display — test-only";
    NSStackView *stack=[[NSStackView alloc] initWithFrame:NSMakeRect(30,30,700,160)];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.spacing=20;
    self.status=[NSTextField labelWithString:@"Virtual display not created yet"];
    self.status.font=[NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightRegular];
    [stack addArrangedSubview:self.status];
    [stack addArrangedSubview:[NSButton buttonWithTitle:@"Connect virtual display" target:self action:@selector(plug:)]];
    [stack addArrangedSubview:[NSButton buttonWithTitle:@"Disconnect virtual display" target:self action:@selector(unplug:)]];
    [stack addArrangedSubview:[NSButton buttonWithTitle:@"Stop display helper" target:NSApp action:@selector(terminate:)]];
    [self.window.contentView addSubview:stack];[self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:NSApplicationDidChangeScreenParametersNotification object:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
@end
int main(int argc,char **argv){@autoreleasepool{NSApplication *a=NSApplication.sharedApplication;a.activationPolicy=NSApplicationActivationPolicyRegular;DisplayDelegate *d=DisplayDelegate.new;a.delegate=d;[a run];}return 0;}
