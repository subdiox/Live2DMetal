#import <CubismFramework.hpp>
#import <Model/CubismUserModel.hpp>
#import <ICubismModelSetting.hpp>
#import <Type/csmRectF.hpp>
#import <Rendering/Metal/CubismOffscreenSurface_Metal.hpp>

using namespace Csm;

@interface Live2DModel : NSObject

@property (nonatomic) CubismUserModel* _Nonnull model;
@property (nonatomic) Rendering::CubismOffscreenSurface_Metal* _Nonnull renderBuffer;
@property (nonatomic, readonly) float canvasWidth;
/// A model setting information
@property (nonatomic) ICubismModelSetting* _Nonnull modelSetting;
/// A directory where model setting is placed
@property (nonatomic) csmString modelHomeDir;
/// An accumulated delta time in seconds
@property (nonatomic) csmFloat32 userTimeSeconds;
/// A list of parameter IDs for eye blinking feature set to the model
@property (nonatomic) csmVector<CubismIdHandle> eyeBlinkIds;
/// A list of parameter IDs for lip syncing feature set to the model
@property (nonatomic) csmVector<CubismIdHandle> lipSyncIds;
/// A list of loaded motions
@property (nonatomic) csmMap<csmString, ACubismMotion*> motions;
/// A list of loaded expressions
@property (nonatomic) csmMap<csmString, ACubismMotion*> expressions;
@property (nonatomic) csmVector<csmRectF> hitArea;
@property (nonatomic) csmVector<csmRectF> userArea;
/// Paramter ID: ParamAngleX
@property (nonatomic) const CubismId* _Nonnull idParamAngleX;
/// Paramter ID: ParamAngleY
@property (nonatomic) const CubismId* _Nonnull idParamAngleY;
/// Paramter ID: ParamAngleZ
@property (nonatomic) const CubismId* _Nonnull idParamAngleZ;
/// Paramter ID: ParamBodyAngleX
@property (nonatomic) const CubismId* _Nonnull idParamBodyAngleX;
/// Paramter ID: ParamEyeBallX
@property (nonatomic) const CubismId* _Nonnull idParamEyeBallX;
/// Paramter ID: ParamEyeBallY
@property (nonatomic) const CubismId* _Nonnull idParamEyeBallY;

- (instancetype _Nonnull)init;
- (void)destroy;
- (void)loadAssetsWithDirectory:(const csmChar* _Nonnull )dir fileName:(const csmChar* _Nonnull)fileName;
- (void)setupModel:(ICubismModelSetting* _Nonnull)setting;
- (void)preloadMotionGroup:(const csmChar* _Nonnull)group;
- (void)releaseMotionGroup:(const csmChar* _Nonnull)group;
- (void)releaseMotions;
- (void)releaseExpressions;
- (void)update:(const csmFloat32)lipSyncValue;
- (CubismMotionQueueEntryHandle _Nonnull)startMotion:(const csmChar* _Nonnull)group
                                                  no:(csmInt32)no
                                            priority:(csmInt32)priority;
- (CubismMotionQueueEntryHandle _Nonnull)startRandomMotion:(const csmChar* _Nonnull)group
                                                  priority:(csmInt32)priority;
- (void)doDraw;
- (void)drawWithMatrix:(CubismMatrix44&)matrix;
- (csmBool)hitTest:(const csmChar* _Nonnull)hitAreaName x:(csmFloat32)x y:(csmFloat32) y;
- (void)setExpressionWithID:(const csmChar* _Nonnull)expressionID;
- (void)setRandomExpression;
- (void)reloadRenderer;
- (void)setupTextures;
- (void)setDraggingWithX:(const csmFloat32)x y:(const csmFloat32)y NS_SWIFT_NAME(setDragging(x:y:));
- (const csmFloat32)getCanvasWidth;
- (bool)isModelAvailable;
@end
