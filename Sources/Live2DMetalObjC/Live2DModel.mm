#import "Live2DModel.h"
#import <Foundation/Foundation.h>
#import <fstream>
#import <vector>
#import "LAppDefine.h"
#import "LAppPal.h"
#import "LAppTextureManager.h"
#import <CubismDefaultParameterId.hpp>
#import <CubismModelSettingJson.hpp>
#import <Id/CubismIdManager.hpp>
#import <Motion/CubismMotion.hpp>
#import <Motion/CubismMotionQueueEntry.hpp>
#import <Physics/CubismPhysics.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import <Utils/CubismString.hpp>

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::DefaultParameterId;
using namespace LAppDefine;

@implementation Live2DModel

#pragma mark - Lifecycle

namespace {
    csmByte* CreateBuffer(const csmChar* path, csmSizeInt* size)
    {
        if (DebugLogEnable)
        {
            LAppPal::PrintLogLn("[APP]create buffer: %s ", path);
        }
        return LAppPal::LoadFileAsBytes(path,size);
    }

    void DeleteBuffer(csmByte* buffer, const csmChar* path = "")
    {
        if (DebugLogEnable)
        {
            LAppPal::PrintLogLn("[APP]delete buffer: %s", path);
        }
        LAppPal::ReleaseBytes(buffer);
    }

    void FinishedMotion(ACubismMotion* self)
    {
        LAppPal::PrintLogLn("Motion Finished: %x", self);
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = new CubismUserModel();
        if (MocConsistencyValidationEnable)
        {
            _model->_mocConsistency = true;
        }
        if (DebugLogEnable)
        {
            _model->_debugMode = true;
        }
        _modelSetting = nil;
        _userTimeSeconds = 0.0f;
        _idParamAngleX = CubismFramework::GetIdManager()->GetId(ParamAngleX);
        _idParamAngleY = CubismFramework::GetIdManager()->GetId(ParamAngleY);
        _idParamAngleZ = CubismFramework::GetIdManager()->GetId(ParamAngleZ);
        _idParamBodyAngleX = CubismFramework::GetIdManager()->GetId(ParamBodyAngleX);
        _idParamEyeBallX = CubismFramework::GetIdManager()->GetId(ParamEyeBallX);
        _idParamEyeBallY = CubismFramework::GetIdManager()->GetId(ParamEyeBallY);
    }
    return self;
}

- (void)destroy
{
    _renderBuffer->DestroyOffscreenSurface();

    [self releaseMotions];
    [self releaseExpressions];

    for (csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
    {
        const csmChar* group = _modelSetting->GetMotionGroupName(i);
        [self releaseMotionGroup:group];
    }

    LAppTextureManager *textureManager = [LAppTextureManager getInstance];

    for (csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
    {
        // テクスチャ名が空文字だった場合は削除処理をスキップ
        if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
        {
            continue;
        }

        //テクスチャ管理クラスからモデルテクスチャを削除する
        csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
        texturePath = _modelHomeDir + texturePath;
        [textureManager releaseTextureByName:texturePath.GetRawString()];
    }

    delete _modelSetting;
}

- (void)loadAssetsWithDirectory:(const csmChar*)dir fileName:(const csmChar*)fileName
{
    _modelHomeDir = dir;

    if (_model->_debugMode)
    {
        LAppPal::PrintLogLn("[APP]load model setting: %s", fileName);
    }

    csmSizeInt size;
    const csmString path = csmString(dir) + fileName;

    csmByte* buffer = CreateBuffer(path.GetRawString(), &size);
    ICubismModelSetting* setting = new CubismModelSettingJson(buffer, size);
    DeleteBuffer(buffer, path.GetRawString());

    [self setupModel:setting];

    if (_model == NULL)
    {
        LAppPal::PrintLogLn("Failed to LoadAssets().");
        return;
    }

    _model->CreateRenderer();

    [self setupTextures];
}


- (void)setupModel:(ICubismModelSetting*) setting
{
    _model->_updating = true;
    _model->_initialized = false;

    _modelSetting = setting;

    csmByte* buffer;
    csmSizeInt size;

    //Cubism Model
    if (strcmp(_modelSetting->GetModelFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetModelFileName();
        path = _modelHomeDir + path;

        if (_model->_debugMode)
        {
            LAppPal::PrintLogLn("[APP]create model: %s", setting->GetModelFileName());
        }

        buffer = CreateBuffer(path.GetRawString(), &size);
        _model->LoadModel(buffer, size, _model->_mocConsistency);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //Expression
    if (_modelSetting->GetExpressionCount() > 0)
    {
        const csmInt32 count = _modelSetting->GetExpressionCount();
        for (csmInt32 i = 0; i < count; i++)
        {
            csmString name = _modelSetting->GetExpressionName(i);
            csmString path = _modelSetting->GetExpressionFileName(i);
            path = _modelHomeDir + path;

            buffer = CreateBuffer(path.GetRawString(), &size);
            ACubismMotion* motion = _model->LoadExpression(buffer, size, name.GetRawString());

            if (motion)
            {
                if (_expressions[name] != NULL)
                {
                    ACubismMotion::Delete(_expressions[name]);
                    _expressions[name] = NULL;
                }
                _expressions[name] = motion;
            }

            DeleteBuffer(buffer, path.GetRawString());
        }
    }

    //Physics
    if (strcmp(_modelSetting->GetPhysicsFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetPhysicsFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        _model->LoadPhysics(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //Pose
    if (strcmp(_modelSetting->GetPoseFileName(), "") != 0)
    {
        csmString path = _modelSetting->GetPoseFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        _model->LoadPose(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    //EyeBlink
    if (_modelSetting->GetEyeBlinkParameterCount() > 0)
    {
        _model->_eyeBlink = CubismEyeBlink::Create(_modelSetting);
    }

    //Breath
    {
        _model->_breath = CubismBreath::Create();

        csmVector<CubismBreath::BreathParameterData> breathParameters;

        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleX, 0.0f, 15.0f, 6.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleY, 0.0f, 8.0f, 3.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleZ, 0.0f, 10.0f, 5.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamBodyAngleX, 0.0f, 4.0f, 15.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(CubismFramework::GetIdManager()->GetId(ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));

        _model->_breath->SetParameters(breathParameters);
    }

    //UserData
    if (strcmp(_modelSetting->GetUserDataFile(), "") != 0)
    {
        csmString path = _modelSetting->GetUserDataFile();
        path = _modelHomeDir + path;
        buffer = CreateBuffer(path.GetRawString(), &size);
        _model->LoadUserData(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    // EyeBlinkIds
    {
        csmInt32 eyeBlinkIdCount = _modelSetting->GetEyeBlinkParameterCount();
        for (csmInt32 i = 0; i < eyeBlinkIdCount; ++i)
        {
            _eyeBlinkIds.PushBack(_modelSetting->GetEyeBlinkParameterId(i));
        }
    }

    // LipSyncIds
    {
        csmInt32 lipSyncIdCount = _modelSetting->GetLipSyncParameterCount();
        for (csmInt32 i = 0; i < lipSyncIdCount; ++i)
        {
            _lipSyncIds.PushBack(_modelSetting->GetLipSyncParameterId(i));
        }
    }

    if (_modelSetting == NULL || _model->_modelMatrix == NULL)
    {
        LAppPal::PrintLogLn("Failed to SetupModel().");
        return;
    }

    //Layout
    csmMap<csmString, csmFloat32> layout;
    _modelSetting->GetLayoutMap(layout);
    _model->_modelMatrix->SetupFromLayout(layout);

    _model->_model->SaveParameters();

    for (csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
    {
        const csmChar* group = _modelSetting->GetMotionGroupName(i);
        [self preloadMotionGroup:group];
    }

    _model->_motionManager->StopAllMotions();

    _model->_updating = false;
    _model->_initialized = true;
}

- (void)preloadMotionGroup:(const csmChar*)group
{
    const csmInt32 count = _modelSetting->GetMotionCount(group);

    for (csmInt32 i = 0; i < count; i++)
    {
        //ex) idle_0
        csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, i);
        csmString path = _modelSetting->GetMotionFileName(group, i);
        path = _modelHomeDir + path;

        if (_model->_debugMode)
        {
            LAppPal::PrintLogLn("[APP]load motion: %s => [%s_%d] ", path.GetRawString(), group, i);
        }

        csmByte* buffer;
        csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        CubismMotion* tmpMotion = static_cast<CubismMotion*>(_model->LoadMotion(buffer, size, name.GetRawString(), FinishedMotion));

        if (tmpMotion)
        {
            csmFloat32 fadeTime = _modelSetting->GetMotionFadeInTimeValue(group, i);
            if (fadeTime >= 0.0f)
            {
                tmpMotion->SetFadeInTime(fadeTime);
            }

            fadeTime = _modelSetting->GetMotionFadeOutTimeValue(group, i);
            if (fadeTime >= 0.0f)
            {
                tmpMotion->SetFadeOutTime(fadeTime);
            }
            tmpMotion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);

            if (_motions[name] != NULL)
            {
                ACubismMotion::Delete(_motions[name]);
            }
            _motions[name] = tmpMotion;
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
}

- (void)releaseMotionGroup:(const csmChar*)group
{
    const csmInt32 count = _modelSetting->GetMotionCount(group);
    for (csmInt32 i = 0; i < count; i++)
    {
        csmString voice = _modelSetting->GetMotionSoundFileName(group, i);
        if (strcmp(voice.GetRawString(), "") != 0)
        {
            csmString path = voice;
            path = _modelHomeDir + path;
        }
    }
}

- (void)releaseMotions
{
    for (csmMap<csmString, ACubismMotion*>::const_iterator iter = _motions.Begin(); iter != _motions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }

    _motions.Clear();
}

- (void)releaseExpressions
{
    for (csmMap<csmString, ACubismMotion*>::const_iterator iter = _expressions.Begin(); iter != _expressions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }

    _expressions.Clear();
}

- (void)update:(const csmFloat32)lipSyncValue
{
    const csmFloat32 deltaTimeSeconds = LAppPal::GetDeltaTime();
    _userTimeSeconds += deltaTimeSeconds;

    _model->_dragManager->Update(deltaTimeSeconds);
    _model->_dragX = _model->_dragManager->GetX();
    _model->_dragY = _model->_dragManager->GetY();

    // モーションによるパラメータ更新の有無
    csmBool motionUpdated = false;

    //-----------------------------------------------------------------
    _model->_model->LoadParameters(); // 前回セーブされた状態をロード
    if (_model->_motionManager->IsFinished())
    {
        // モーションの再生がない場合、待機モーションの中からランダムで再生する
        [self startRandomMotion:MotionGroupIdle priority:PriorityIdle];
    }
    else
    {
        motionUpdated = _model->_motionManager->UpdateMotion(_model->_model, deltaTimeSeconds); // モーションを更新
    }
    _model->_model->SaveParameters(); // 状態を保存
    //-----------------------------------------------------------------

    // 不透明度
    _model->_opacity = _model->_model->GetModelOpacity();

    // まばたき
    if (!motionUpdated)
    {
        if (_model->_eyeBlink != NULL)
        {
            // メインモーションの更新がないとき
            _model->_eyeBlink->UpdateParameters(_model->_model, deltaTimeSeconds); // 目パチ
        }
    }

    if (_model->_expressionManager != NULL)
    {
        _model->_expressionManager->UpdateMotion(_model->_model, deltaTimeSeconds); // 表情でパラメータ更新（相対変化）
    }

    //ドラッグによる変化
    //ドラッグによる顔の向きの調整
    _model->_model->AddParameterValue(_idParamAngleX, _model->_dragX * 30); // -30から30の値を加える
    _model->_model->AddParameterValue(_idParamAngleY, _model->_dragY * 30);
    _model->_model->AddParameterValue(_idParamAngleZ, _model->_dragX * _model->_dragY * -30);

    //ドラッグによる体の向きの調整
    _model->_model->AddParameterValue(_idParamBodyAngleX, _model->_dragX * 10); // -10から10の値を加える

    //ドラッグによる目の向きの調整
    _model->_model->AddParameterValue(_idParamEyeBallX, _model->_dragX); // -1から1の値を加える
    _model->_model->AddParameterValue(_idParamEyeBallY, _model->_dragY);

    // 呼吸など
    if (_model->_breath != NULL)
    {
        _model->_breath->UpdateParameters(_model->_model, deltaTimeSeconds);
    }

    // 物理演算の設定
    if (_model->_physics != NULL)
    {
        _model->_physics->Evaluate(_model->_model, deltaTimeSeconds);
    }

    // リップシンクの設定
    if (_model->_lipSync)
    {
        for (csmUint32 i = 0; i < _lipSyncIds.GetSize(); ++i)
        {
            _model->_model->AddParameterValue(_lipSyncIds[i], lipSyncValue, 0.8f);
        }
    }

    // ポーズの設定
    if (_model->_pose != NULL)
    {
        _model->_pose->UpdateParameters(_model->_model, deltaTimeSeconds);
    }

    _model->_model->Update();

}

- (CubismMotionQueueEntryHandle)startMotion:(const csmChar*)group
                                         no:(csmInt32)no
                                   priority:(csmInt32)priority
{
    if (priority == PriorityForce)
    {
        _model->_motionManager->SetReservePriority(priority);
    }
    else if (!_model->_motionManager->ReserveMotion(priority))
    {
        if (_model->_debugMode)
        {
            LAppPal::PrintLogLn("[APP]can't start motion.");
        }
        return InvalidMotionQueueEntryHandleValue;
    }

    const csmString fileName = _modelSetting->GetMotionFileName(group, no);

    //ex) idle_0
    csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, no);
    CubismMotion* motion = static_cast<CubismMotion*>(_motions[name.GetRawString()]);
    csmBool autoDelete = false;

    if (motion == NULL)
    {
        csmString path = fileName;
        path = _modelHomeDir + path;

        csmByte* buffer;
        csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        motion = static_cast<CubismMotion*>(_model->LoadMotion(buffer, size, NULL, FinishedMotion));

        if (motion)
        {
            csmFloat32 fadeTime = _modelSetting->GetMotionFadeInTimeValue(group, no);
            if (fadeTime >= 0.0f)
            {
                motion->SetFadeInTime(fadeTime);
            }

            fadeTime = _modelSetting->GetMotionFadeOutTimeValue(group, no);
            if (fadeTime >= 0.0f)
            {
                motion->SetFadeOutTime(fadeTime);
            }
            motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
            autoDelete = true; // 終了時にメモリから削除
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
    else
    {
        motion->SetFinishedMotionHandler(FinishedMotion);
    }

    //voice
    csmString voice = _modelSetting->GetMotionSoundFileName(group, no);
    if (strcmp(voice.GetRawString(), "") != 0)
    {
        csmString path = voice;
        path = _modelHomeDir + path;
    }

    if (_model->_debugMode)
    {
        LAppPal::PrintLogLn("[APP]start motion: [%s_%d]", group, no);
    }
    return _model->_motionManager->StartMotionPriority(motion, autoDelete, priority);
}

- (CubismMotionQueueEntryHandle)startRandomMotion:(const csmChar*)group
                                         priority:(csmInt32)priority
{
    if (_modelSetting->GetMotionCount(group) == 0)
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    csmInt32 no = rand() % _modelSetting->GetMotionCount(group);

    return [self startMotion:group
                          no:no
                    priority:priority];
}

- (void)doDraw
{
    if (_model->_model == NULL)
    {
        return;
    }

    _model->GetRenderer<Rendering::CubismRenderer_Metal>()->DrawModel();
}

- (void)drawWithMatrix:(CubismMatrix44&)matrix
{
    if (_model->_model == NULL)
    {
        return;
    }

    matrix.MultiplyByMatrix(_model->_modelMatrix);

    _model->GetRenderer<Rendering::CubismRenderer_Metal>()->SetMvpMatrix(&matrix);

    [self doDraw];
}

- (csmBool)hitTest:(const csmChar*)hitAreaName x:(csmFloat32)x y:(csmFloat32)y
{
    // 透明時は当たり判定なし。
    if (_model->_opacity < 1)
    {
        return false;
    }
    const csmInt32 count = _modelSetting->GetHitAreasCount();
    for (csmInt32 i = 0; i < count; i++)
    {
        if (strcmp(_modelSetting->GetHitAreaName(i), hitAreaName) == 0)
        {
            const CubismIdHandle drawID = _modelSetting->GetHitAreaId(i);
            return _model->IsHit(drawID, x, y);
        }
    }
    return false; // 存在しない場合はfalse
}

- (void)setExpressionWithID:(const csmChar*)expressionID
{
    ACubismMotion* motion = _expressions[expressionID];
    if (_model->_debugMode)
    {
        LAppPal::PrintLogLn("[APP]expression: [%s]", expressionID);
    }

    if (motion != NULL)
    {
        _model->_expressionManager->StartMotionPriority(motion, false, PriorityForce);
    }
    else
    {
        if (_model->_debugMode)
        {
            LAppPal::PrintLogLn("[APP]expression[%s] is null ", expressionID);
        }
    }
}

- (void)setRandomExpression
{
    if (_expressions.GetSize() == 0)
    {
        return;
    }

    csmInt32 no = rand() % _expressions.GetSize();
    csmMap<csmString, ACubismMotion*>::const_iterator map_ite;
    csmInt32 i = 0;
    for (map_ite = _expressions.Begin(); map_ite != _expressions.End(); map_ite++)
    {
        if (i == no)
        {
            csmString name = (*map_ite).First;
            [self setExpressionWithID:name.GetRawString()];
            return;
        }
        i++;
    }
}

- (void)reloadRenderer
{
    _model->DeleteRenderer();

    _model->CreateRenderer();

    [self setupTextures];
}

- (void)setupTextures
{
    LAppTextureManager *textureManager = [LAppTextureManager getInstance];

    for (csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
    {
        // テクスチャ名が空文字だった場合はロード・バインド処理をスキップ
        if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
        {
            continue;
        }

        //Metalテクスチャにテクスチャをロードする
        csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
        texturePath = _modelHomeDir + texturePath;

        TextureInfo* texture = [textureManager createTextureFromPngFile:texturePath.GetRawString()];
        id <MTLTexture> mtlTextueNumber = texture->id;

        //Metal
        _model->GetRenderer<Rendering::CubismRenderer_Metal>()->BindTexture(modelTextureNumber, mtlTextueNumber);
    }

#ifdef PREMULTIPLIED_ALPHA_ENABLE
    _model->GetRenderer<Rendering::CubismRenderer_Metal>()->IsPremultipliedAlpha(true);
#else
    _model->GetRenderer<Rendering::CubismRenderer_Metal>()->IsPremultipliedAlpha(false);
#endif
}

- (void)setDraggingWithX:(const csmFloat32)x y:(const csmFloat32)y {
    _model->SetDragging(x, y);
}

- (const csmFloat32)getCanvasWidth {
    return _model->GetModel()->GetCanvasWidth();
}

- (bool)isModelAvailable {
    return _model->GetModel() != NULL;
}

@end
