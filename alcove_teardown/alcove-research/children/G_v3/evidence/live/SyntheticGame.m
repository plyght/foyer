#import <Cocoa/Cocoa.h>
@interface GameDelegate : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *state;
@end
@implementation GameDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    BOOL listed = [bid isEqualToString:@"com.nvidia.gfnpc.mall"];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = listed ? @"Synthetic fixed-ID control — NOT GeForce NOW" : @"Synthetic category control — neutral bundle ID";
    self.window.delegate = self;
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    self.window.backgroundColor = [NSColor colorWithRed:0.82 green:0.94 blue:0.97 alpha:1];
    NSView *v=self.window.contentView;
    NSStackView *stack=[[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation=NSUserInterfaceLayoutOrientationVertical;
    stack.alignment=NSLayoutAttributeLeading;
    stack.spacing=22;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],[stack.widthAnchor constraintEqualToConstant:930]]];
    NSArray *texts=@[listed?@"SYNTHETIC FIXED-ID CONTROL":@"SYNTHETIC CATEGORY CONTROL",
        [@"Bundle identifier: " stringByAppendingString:bid],
        [@"LSApplicationCategoryType: " stringByAppendingString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"LSApplicationCategoryType"]],
        @"This is a local test window. No real game, GeForce app, or network activity.",
        @"Goal: isolate Hide while gaming with Hide in fullscreen OFF."];
    for (NSString *t in texts) {
        NSTextField *f=[NSTextField labelWithString:t];
        f.font=[NSFont systemFontOfSize:([t hasPrefix:@"SYNTHETIC"]?30:20) weight:NSFontWeightMedium];
        [stack addArrangedSubview:f];
    }
    NSButton *full=[NSButton buttonWithTitle:@"Toggle native fullscreen" target:self action:@selector(full:)];
    full.font=[NSFont systemFontOfSize:20];
    [stack addArrangedSubview:full];
    self.state=[NSTextField labelWithString:@"State: WINDOWED"];
    self.state.font=[NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightMedium];
    [stack addArrangedSubview:self.state];
    NSButton *quit=[NSButton buttonWithTitle:@"Stop synthetic helper" target:NSApp action:@selector(terminate:)];
    [stack addArrangedSubview:quit];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)full:(id)s { [self.window toggleFullScreen:nil]; }
- (void)windowDidEnterFullScreen:(NSNotification *)n { self.state.stringValue=@"State: NATIVE FULLSCREEN"; }
- (void)windowDidExitFullScreen:(NSNotification *)n { self.state.stringValue=@"State: WINDOWED"; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
@end
int main(int argc,char **argv) { @autoreleasepool {
    NSApplication *a=NSApplication.sharedApplication; a.activationPolicy=NSApplicationActivationPolicyRegular;
    GameDelegate *d=GameDelegate.new; a.delegate=d; [a run];
} return 0; }
