#import <Cocoa/Cocoa.h>
int main(int argc,char **argv){@autoreleasepool{
    int key=(argc>1 && strcmp(argv[1],"down")==0)?1:0;
    for(int state=0;state<2;state++){
        NSEvent *e=[NSEvent otherEventWithType:NSEventTypeSystemDefined location:NSZeroPoint modifierFlags:(state?0xB00:0xA00) timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:0 context:nil subtype:8 data1:(key<<16)|((state?0xB:0xA)<<8) data2:-1];
        CGEventPost(kCGHIDEventTap,e.CGEvent);
    }
}return 0;}
