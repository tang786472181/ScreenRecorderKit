//
//  ScreenRecordManager.m
//  录制屏幕框架
//
//  Created by huang on 2019/5/24.
//  Copyright © 2019 huang. All rights reserved.
//

#import "ScreenRecordManager.h"
#import <ReplayKit/ReplayKit.h>
#import "RPPreviewViewController+MovieURL.h"
#import <Photos/Photos.h>

#define kWeakSelf(type) __weak typeof(type) weak##type = type;
#define kStrongSelf(type) __strong typeof(type) type = weak##type;


#if DEBUG
#define SRLog(fmt, ...) NSLog((@"[文件名:%s]\n" "[函数名:%s]\n" "[行号:%d] \n" fmt"\n\n"), __FILE__, __FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define SRLog(...) {}
#endif

@interface ScreenRecordManager () <RPPreviewViewControllerDelegate,
                                   RPScreenRecorderDelegate>
@end

@implementation ScreenRecordManager

static ScreenRecordManager *_screenManager = nil;

+ (instancetype)shareManager {
  if (_screenManager == nil) {
    _screenManager = [[ScreenRecordManager alloc] init];
  }
  return _screenManager;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _screenManager = [super allocWithZone:zone];
  });
  return _screenManager;
}

- (id)copyWithZone:(NSZone *)zone {
  return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
  return self;
}

- (instancetype)init {
  if (self = [super init]) {
  }
  return self;
}

// 开始录制屏幕
- (void)screenRecSuc:(void (^)(void))suc failure:(srerrorinfo)errorInfo {
  kWeakSelf(self);
  RPScreenRecorder *recorder = RPScreenRecorder.sharedRecorder;
  recorder.delegate = self;
  recorder.microphoneEnabled = YES;
  NSString *version = [UIDevice currentDevice].systemVersion;
  if ([version doubleValue] < 9.0) {
    SRErrorHandle *err = [[SRErrorHandle alloc] init];
    err.code = -4;
    err.msg = @"iOS9.0之后的系统才可以使用录屏功能";
    errorInfo(err);
  }
  // 先检查系统版本
  if (@available(iOS 10.0, *)) {
    if (recorder.isRecording) { // 正在录制中不能在录制了
      SRErrorHandle *err = [[SRErrorHandle alloc] init];
      err.code = -1;
      err.msg = @"录屏正在进行，无法再次开启录屏功能";
      errorInfo(err);
    }
    [recorder startRecordingWithHandler:^(NSError *_Nullable error) {
      if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          weakself.isRecording = YES;
          suc();
        });
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          weakself.isRecording = NO;
          SRErrorHandle *err = [[SRErrorHandle alloc] initWithError:error];
          errorInfo(err);
        });
      }
    }];
  } else {
    if (@available(iOS 9.0, *)) {
      if (recorder.isRecording) { // 正在录制中不能在录制了
        weakself.isRecording = NO;
        SRErrorHandle *err = [[SRErrorHandle alloc] init];
        err.code = -1;
        err.msg = @"正在录制中";
        errorInfo(err);
      }
      [recorder
          startRecordingWithMicrophoneEnabled:YES
                                      handler:^(NSError *_Nullable error) {
                                        if (!error) {
                                          dispatch_async(
                                              dispatch_get_main_queue(), ^{
                                                weakself.isRecording = YES;
                                                suc();
                                              });
                                        } else {
                                          dispatch_async(
                                              dispatch_get_main_queue(), ^{
                                                weakself.isRecording = NO;
                                                SRErrorHandle *err =
                                                    [[SRErrorHandle alloc]
                                                        initWithError:error];
                                                errorInfo(err);
                                              });
                                        }
                                      }];
    }
  }
}

// 停止录制屏幕
- (void)stopRecSuc:(void (^)(void))suc failure:(srerrorinfo)errorInfo {
  SRLog(@"结束开始");
  kWeakSelf(self);
  if (!RPScreenRecorder.sharedRecorder.isRecording) {
    SRErrorHandle *err = [[SRErrorHandle alloc] init];
    err.code = -2;
    err.msg = @"没有正在录制的进程";
    errorInfo(err);
  } else {
    [[RPScreenRecorder sharedRecorder]
        stopRecordingWithHandler:^(
            RPPreviewViewController *_Nullable previewViewController,
            NSError *_Nullable error) {
          SRLog(@"结束回调");
          if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
              SRErrorHandle *err = [[SRErrorHandle alloc] initWithError:error];
              errorInfo(err);
            });
          } else {
            dispatch_async(dispatch_get_main_queue(), ^{
              weakself.isRecording = NO;
              suc();
              if (@available(iOS 14, *)) {
                if (previewViewController) {
                  previewViewController.previewControllerDelegate = self;
                  __kindof UIViewController *vc = self.screenRecordDelegate;
                  [vc presentViewController:previewViewController
                                   animated:YES
                                 completion:nil];
                }
              } else {
                if ([previewViewController
                        respondsToSelector:@selector(movieURL)]) {
                  NSURL *videoURL = [previewViewController.movieURL copy];
                  if (!videoURL) {
                    return;
                  }
                  BOOL compatible =
                      UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(
                          [videoURL path]);
                  if (compatible) {
                    UISaveVideoAtPathToSavedPhotosAlbum(
                        [videoURL path], self,
                        @selector(video:didFinishSavingWithError:contextInfo:),
                        nil);
                  }
                }
              }
            });
          }
        }];
  }
}
#pragma mark -保存视频完成之后的回调 - Private iOS14一下
- (void)video:(NSString *)videoPath
    didFinishSavingWithError:(NSError *)error
                 contextInfo:(void *)contextInfo {
  if (self.screenRecordDelegate &&
      [self.screenRecordDelegate
          respondsToSelector:@selector(savedPhotoImage:
                                 didFinishSavingWithError:
                                              contextInfo:)]) {
    [self.screenRecordDelegate savedPhotoImage:videoPath
                      didFinishSavingWithError:error
                                   contextInfo:contextInfo];
  }
  __block NSData *data;
  __block BOOL isError; // 判断进入didFinishSavingWithError之后有没有错误
  if (error) {
    isError = YES;
  } else {
    isError = NO;
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors =
        @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate"
                                         ascending:YES] ]; //按创建日期获取
    PHFetchResult *assetsFetchResults =
        [PHAsset fetchAssetsWithOptions:options];
    PHAsset *phasset = [assetsFetchResults lastObject];
    if (phasset) {
      if (phasset.mediaType == PHAssetMediaTypeVideo) {
        PHImageManager *manager = [PHImageManager defaultManager];
        [manager requestAVAssetForVideo:phasset
                                options:nil
                          resultHandler:^(AVAsset *_Nullable asset,
                                          AVAudioMix *_Nullable audioMix,
                                          NSDictionary *_Nullable info) {
                            isError = NO;
                            AVURLAsset *urlAsset = (AVURLAsset *)asset;
                            NSURL *videoURL = urlAsset.URL;
                            data = [NSData dataWithContentsOfURL:videoURL];
                            dispatch_async(dispatch_get_main_queue(), ^{
                              // delegate
                              if (self.screenRecordDelegate &&
                                  [self.screenRecordDelegate
                                      respondsToSelector:
                                          @selector(savedVideoData:
                                              didFinishSavingWithError:)]) {
                                [self.screenRecordDelegate
                                              savedVideoData:data
                                    didFinishSavingWithError:isError];
                              }
                            });
                          }];

      } else {
        isError = YES;
        // delegate
        if (self.screenRecordDelegate &&
            [self.screenRecordDelegate
                respondsToSelector:@selector(savedVideoData:
                                       didFinishSavingWithError:)]) {
          [self.screenRecordDelegate savedVideoData:data
                           didFinishSavingWithError:isError];
        }
      }
    } else {
      isError = NO;
      // delegate
      if (self.screenRecordDelegate &&
          [self.screenRecordDelegate
              respondsToSelector:@selector(savedVideoData:
                                     didFinishSavingWithError:)]) {
        [self.screenRecordDelegate savedVideoData:data
                         didFinishSavingWithError:isError];
      }
    }
  }
}

//-(void)deletePhoto:(PHAsset *)asset{
//    PHFetchOptions *photosOptions = [[PHFetchOptions alloc] init];
//    photosOptions.sortDescriptors = @[[NSSortDescriptor
//    sortDescriptorWithKey:@"creationDate" ascending:NO]];
//
//    PHFetchResult<PHAssetCollection *>
//    *assetSmartCollection=[PHAssetCollection
//    fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum
//    subtype:PHAssetCollectionSubtypeSmartAlbumRecentlyAdded options:nil];
//    if (assetSmartCollection.count>0) {
//
//        PHAssetCollection*recentlyAddedAlbum=
//        assetSmartCollection.firstObject;
//        NSString*albumName= recentlyAddedAlbum.localizedTitle;
//        //按照相片的创造时间查询相册里面的图片
//        PHFetchOptions *photosOptions = [[PHFetchOptions alloc] init];
//        photosOptions.sortDescriptors = @[[NSSortDescriptor
//        sortDescriptorWithKey:@"creationDate" ascending:NO]];
//
//    PHFetchResult *assetResult = [PHAsset
//    fetchAssetsInAssetCollection:recentlyAddedAlbum options:photosOptions];
//
//    [assetResult enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL
//    *stop) {
//
//        if ([asset isEqual:obj]) {
//            //删除图片
//            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//                [PHAssetChangeRequest deleteAssets:@[obj]];
//            } completionHandler:^(BOOL success, NSError *error) {
//
//                if (success) {
//
//                }else{
//                        NSLog(@"Error: %@", error);
//                }
//
//            }];
//        }
//
//    }];
//
//    }
//}

#pragma mark - **************** RPPreviewViewControllerDelegate ****************
/* @abstract Called when the view controller is finished. */
- (void)previewControllerDidFinish:
    (RPPreviewViewController *)previewController {
  [previewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)previewController:(RPPreviewViewController *)previewController
    didFinishWithActivityTypes:(NSSet<NSString *> *)activityTypes {
  [previewController dismissViewControllerAnimated:YES completion:nil];
  if ([activityTypes
          containsObject:@"com.apple.UIKit.activity.SaveToCameraRoll"]) {
    SRLog(@"保存到相册成功");
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors =
        @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate"
                                         ascending:YES] ]; //按创建日期获取
    PHFetchResult *assetsFetchResults =
        [PHAsset fetchAssetsWithOptions:options];
    PHAsset *phasset = [assetsFetchResults lastObject];
    if (phasset) {
      if (phasset.mediaType == PHAssetMediaTypeVideo) {
        PHImageManager *manager = [PHImageManager defaultManager];
        [manager requestAVAssetForVideo:phasset
                                options:nil
                          resultHandler:^(AVAsset * asset,
                                          AVAudioMix * audioMix,
                                          NSDictionary * info) {
                            AVURLAsset *urlAsset = (AVURLAsset *)asset;
                            NSURL *videoURL = urlAsset.URL;
                            NSData *data =
                                [NSData dataWithContentsOfURL:videoURL];
                            dispatch_async(dispatch_get_main_queue(), ^{
                              // delegate
                              if (self.screenRecordDelegate &&
                                  [self.screenRecordDelegate
                                      respondsToSelector:
                                          @selector(savedVideoData:
                                              didFinishSavingWithError:)]) {
                                [self.screenRecordDelegate savedVideoData:data
                                                 didFinishSavingWithError:NO];
                              }

                            });

                          }];
      }
    }
  }
}

#pragma mark - RPScreenRecorder Delegate
- (void)screenRecorder:(RPScreenRecorder *)screenRecorder
    didStopRecordingWithError:(NSError *)error
        previewViewController:
            (nullable RPPreviewViewController *)previewViewController {
  if (self.screenRecordDelegate &&
      [self.screenRecordDelegate
          respondsToSelector:@selector(recStateDidChange:withError:)]) {
    RecState state = RecState_Stop;
    [self.screenRecordDelegate recStateDidChange:state withError:NULL];
  }
}

- (void)screenRecorder:(RPScreenRecorder *)screenRecorder
    didStopRecordingWithPreviewViewController:
        (RPPreviewViewController *)previewViewController
                                        error:(NSError *)error {
  if (self.screenRecordDelegate &&
      [self.screenRecordDelegate
          respondsToSelector:@selector(recStateDidChange:withError:)]) {
    RecState state = RecState_Stop;
    [self.screenRecordDelegate recStateDidChange:state withError:NULL];
  }
}

// 监听replaykit是否可用，比如状态发生变化（比如录制过程中，切入设置，关闭权限。）会回调该方法。
- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder *)screenRecorder {
}

#pragma mark - Setter
- (void)setIsRecording:(BOOL)isRecording {
  _isRecording = isRecording;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.screenRecordDelegate &&
        [self.screenRecordDelegate
            respondsToSelector:@selector(recStateDidChange:withError:)]) {
      RecState state;
      if (isRecording) {
        state = RecState_Rec;
      } else {
        state = RecState_Stop;
      }
      [self.screenRecordDelegate recStateDidChange:state withError:NULL];
    }
  });
}

@end
