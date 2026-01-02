// Standalone Metal Backend Test
// Compiles and runs independently of DRAWEXE

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <cmath>

// Simple Metal test - renders animated triangle

@interface MetalView : NSView
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLDepthStencilState> depthState;
@property (nonatomic, strong) CAMetalLayer* metalLayer;
@property (nonatomic, strong) id<MTLTexture> depthTexture;
@property (nonatomic, assign) int frameCount;
@property (nonatomic, strong) NSTimer* renderTimer;
@end

@implementation MetalView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.frameCount = 0;
        [self setupMetal];
    }
    return self;
}

- (CALayer*)makeBackingLayer {
    CAMetalLayer* layer = [CAMetalLayer layer];
    return layer;
}

- (void)setupMetal {
    // Get Metal device
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"Metal is not supported on this device");
        return;
    }
    NSLog(@"Metal device: %@", _device.name);

    // Get the Metal layer
    _metalLayer = (CAMetalLayer*)self.layer;
    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;

    // Create command queue
    _commandQueue = [_device newCommandQueue];

    // Create shaders
    NSString* shaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
    float4   color;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut vertex_main(
    const device float3* positions [[buffer(0)]],
    constant Uniforms& uniforms    [[buffer(1)]],
    uint vid                       [[vertex_id]])
{
    VertexOut out;
    float4 worldPos = float4(positions[vid], 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    return out;
}

fragment float4 fragment_main(
    VertexOut in                [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]])
{
    return uniforms.color;
}
)";

    NSError* error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"Failed to compile shaders: %@", error);
        return;
    }
    NSLog(@"Shaders compiled successfully");

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragment_main"];

    // Create pipeline
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline: %@", error);
        return;
    }
    NSLog(@"Pipeline created successfully");

    // Create depth state
    MTLDepthStencilDescriptor* depthDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthDesc];

    NSLog(@"Metal setup complete!");
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        _metalLayer.contentsScale = self.window.backingScaleFactor;
        [self updateDrawableSize];

        // Start render timer
        _renderTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                        target:self
                                                      selector:@selector(render)
                                                      userInfo:nil
                                                       repeats:YES];
    }
}

- (void)updateDrawableSize {
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;

    CGFloat scale = self.window ? self.window.backingScaleFactor : 1.0;
    NSUInteger width = (NSUInteger)(size.width * scale);
    NSUInteger height = (NSUInteger)(size.height * scale);

    if (width == 0 || height == 0) return;

    _metalLayer.drawableSize = CGSizeMake(width, height);

    // Create depth texture
    MTLTextureDescriptor* depthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                         width:width
                                                                                        height:height
                                                                                     mipmapped:NO];
    depthDesc.storageMode = MTLStorageModePrivate;
    depthDesc.usage = MTLTextureUsageRenderTarget;
    _depthTexture = [_device newTextureWithDescriptor:depthDesc];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateDrawableSize];
}

- (void)render {
    if (!_pipelineState) return;
    if (!_depthTexture) {
        [self updateDrawableSize];
        if (!_depthTexture) return;
    }

    _frameCount++;

    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.15, 0.15, 0.2, 1.0);

    passDesc.depthAttachment.texture = _depthTexture;
    passDesc.depthAttachment.loadAction = MTLLoadActionClear;
    passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
    passDesc.depthAttachment.clearDepth = 1.0;

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

    // Set viewport
    MTLViewport viewport;
    viewport.originX = 0;
    viewport.originY = 0;
    viewport.width = drawable.texture.width;
    viewport.height = drawable.texture.height;
    viewport.znear = 0;
    viewport.zfar = 1;
    [encoder setViewport:viewport];

    // Set pipeline
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setDepthStencilState:_depthState];

    // Triangle vertices
    float vertices[] = {
         0.0f,  0.5f, 0.5f,
        -0.5f, -0.5f, 0.5f,
         0.5f, -0.5f, 0.5f
    };

    // Uniforms with animated color
    struct {
        float modelViewMatrix[16];
        float projectionMatrix[16];
        float color[4];
    } uniforms;

    // Identity matrices
    memset(uniforms.modelViewMatrix, 0, sizeof(uniforms.modelViewMatrix));
    uniforms.modelViewMatrix[0] = 1.0f;
    uniforms.modelViewMatrix[5] = 1.0f;
    uniforms.modelViewMatrix[10] = 1.0f;
    uniforms.modelViewMatrix[15] = 1.0f;

    memset(uniforms.projectionMatrix, 0, sizeof(uniforms.projectionMatrix));
    uniforms.projectionMatrix[0] = 1.0f;
    uniforms.projectionMatrix[5] = 1.0f;
    uniforms.projectionMatrix[10] = 1.0f;
    uniforms.projectionMatrix[15] = 1.0f;

    // Animated rainbow color
    float t = (_frameCount % 360) / 360.0f;
    uniforms.color[0] = 0.5f + 0.5f * sinf(t * 6.28f);
    uniforms.color[1] = 0.5f + 0.5f * sinf(t * 6.28f + 2.09f);
    uniforms.color[2] = 0.5f + 0.5f * sinf(t * 6.28f + 4.18f);
    uniforms.color[3] = 1.0f;

    [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];

    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

- (void)dealloc {
    [_renderTimer invalidate];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow* window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    NSRect frame = NSMakeRect(100, 100, 800, 600);

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled |
                                                    NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    _window.title = @"Metal Backend Test - Animated Triangle";

    MetalView* metalView = [[MetalView alloc] initWithFrame:frame];
    _window.contentView = metalView;

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSLog(@"Window created and visible!");
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        // Create menu
        NSMenu* menubar = [[NSMenu alloc] init];
        NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
        [menubar addItem:appMenuItem];
        NSMenu* appMenu = [[NSMenu alloc] init];
        NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                          action:@selector(terminate:)
                                                   keyEquivalent:@"q"];
        [appMenu addItem:quitItem];
        appMenuItem.submenu = appMenu;
        app.mainMenu = menubar;

        [app run];
    }
    return 0;
}
