//
//  ITPViewControllerDelegate.h
//  iTunesPicker
//
//  Created by Denis Berton on 25/04/14.
//  Copyright (c) 2014 appcorner.it. All rights reserved.
//


@protocol ITPPickerTableViewControllerDelegate<NSObject>
-(ACKEntitiesContainer*)entitiesDatasources;
@optional
-(void)selectEntity:(ACKITunesEntity*)entity;
-(void)openITunesEntityDetail:(ACKITunesEntity*)entity;
-(void)showLoadingHUD:(BOOL)loading;
-(void)showPickerAtIndex:(NSInteger)index;
@end