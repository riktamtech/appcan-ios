/**
 *
 *	@file   	: ACEPluginParser.m  in AppCanEngine Project
 *
 *	@author 	: CeriNo
 *
 *	@date   	: Created on 15/12/15
 *
 *	@copyright 	: 2015 The AppCan Open Source Project.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "ACEPluginParser.h"
#import <Ono/Ono.h>
#import "BUtility.h"
#import "ACEPluginModel.h"
#import "WidgetOneDelegate.h"


@interface ACEPluginInfo()
@property (nonatomic,strong)NSString *uexName;
@property (nonatomic,strong)NSMutableDictionary<NSString *,NSString *> *methods;
@property (nonatomic,strong)NSMutableDictionary<NSString *,NSString *> *properties;
@end
@implementation ACEPluginInfo

- (instancetype)initWithName:(NSString *)uexName;
{
    self = [super init];
    if (self) {
        _uexName=uexName;
        //methods 不用array 是为了避免判断重复添加
        _methods=[NSMutableDictionary dictionary];
        _properties=[NSMutableDictionary dictionary];
    }
    return self;
}
-(void)updateWithXMLElement:(ONOXMLElement *)XMLElement{
    NSArray *newMethods=[XMLElement childrenWithTag:@"method"];
    for (ONOXMLElement *aMethod in newMethods) {
        NSString *methodName=aMethod[@"name"];
        if(methodName && methodName.length >0){
            [self.methods setValue:@"" forKey:methodName];
        }
    }
    NSArray *newProperties=[XMLElement childrenWithTag:@"property"];
    for (ONOXMLElement *aProperty in newProperties) {
        NSString *propertyName=aProperty[@"property"];
        if(propertyName && propertyName.length >0 && aProperty.stringValue){
            [self.methods setValue:aProperty.stringValue forKey:propertyName];
        }
    }
}
@end




@interface ACEPluginParser ()
@property NSMutableDictionary<NSString *,ACEPluginInfo *> *pluginDict;
@end
@implementation ACEPluginParser





- (instancetype)init
{
    self = [super init];
    if (self) {
        _pluginDict=[NSMutableDictionary dictionary];
        for (NSString *xmlPath in [self XMLPaths]) {
            [self parsePluginXMLByPath:xmlPath];
        }
    }
    return self;
}

#pragma mark - Interface
- (NSString *)pluginBaseJS{
    __block NSMutableString *baseJS=[NSMutableString stringWithFormat:@"\n"];
    [self.pluginDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, ACEPluginInfo * _Nonnull obj, BOOL * _Nonnull stop) {
        [baseJS appendString:[self JSForPlugin:obj]];
    }];
    return baseJS;
}
- (NSArray *)classNameArray{
    if(!self.pluginDict){
        return @[];
    }
    return self.pluginDict.allKeys;
}

#pragma mark - Private


- (NSArray *)XMLPaths{
    NSMutableArray *paths=[NSMutableArray array];
    
    NSString *originXML=[NSString stringWithFormat:@"%@/plugin.xml",[[NSBundle mainBundle] resourcePath]];
    [paths addObject:originXML];
    
    NSString *dynamicXML=[[BUtility dynamicPluginFrameworkFolderPath]stringByAppendingPathComponent:@"plugin.xml"];
    [paths addObject:dynamicXML];
    
#ifdef DEBUG
    NSString *debugPath=[BUtility wgtResPath:@"res://plugin.xml"];
    [paths addObject:debugPath];
#endif
    return paths;
}


- (void)parsePluginXMLByPath:(NSString *)XMLPath{
    NSData *XMLData=[[NSData alloc]initWithContentsOfFile:XMLPath];
    if(!XMLData){
        return;
    }
    NSError *error=nil;
    ONOXMLDocument *xml=[ONOXMLDocument XMLDocumentWithData:XMLData error:&error];
   
    if(error){
        return;
    }
    NSArray *plugins=[[xml rootElement] childrenWithTag:@"plugin"];
    for (ONOXMLElement *pluginElement in plugins) {
        [self updatePluginInfo:pluginElement];
    }
}

- (void)updatePluginInfo:(ONOXMLElement *)pluginElement{
    NSString *uexName=pluginElement[@"name"];
    if(!uexName || ![uexName hasPrefix:@"uex"]||[uexName length]<4){
        return;
    }
    ACEPluginInfo *pluginInfo =[self.pluginDict objectForKey:uexName];
    if(!pluginInfo){
        pluginInfo=[[ACEPluginInfo alloc]initWithName:uexName];
    }
    [pluginInfo updateWithXMLElement:pluginElement];
    [self.pluginDict setValue:pluginInfo forKey:uexName];
    
    NSString *global=pluginElement[@"global"];
    if(global && [global isEqual:@"true"]){
        [self addPluginToGlobal:uexName];
    }
}

- (void)addPluginToGlobal:(NSString *)name
{
    if (name == nil) {
        return;
    }
    ACEPluginModel *model = [[ACEPluginModel alloc] init];
    
    model.pluginName = name;
    model.pluginObj = nil;
    
    WidgetOneDelegate *app = (WidgetOneDelegate *)[UIApplication sharedApplication].delegate;
    
    [app.globalPluginDict setObject:model forKey:name];
    
}

- (NSString *)JSForPlugin:(ACEPluginInfo *)pluginInfo{
    __block NSMutableString *JS=[NSMutableString stringWithFormat:@"\n"];
    [JS appendFormat:@"window.%@={}\n",pluginInfo.uexName];
    [pluginInfo.properties enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        [JS appendFormat:@"%@.%@=%@\n",pluginInfo.uexName,key,obj];
    }];
    [pluginInfo.methods enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        NSString *methodJS=[NSString stringWithFormat:@"%@.%@=function(){uex.exec('%@.%@/'+uexJoin(arguments));};\n",pluginInfo.uexName,key,pluginInfo.uexName,key];;
        //uexDataBaseMgr的特例情况
        if ([pluginInfo.uexName isEqualToString:@"uexDataBaseMgr"] && [key isEqualToString:@"transaction"]) {
            methodJS = @"uexDataBaseMgr.transaction=function(inDBName,inOpId,inFunc){var temp = encodeURIComponent(inDBName)+uex_s_uex+encodeURIComponent(inOpId);uex.exec('uexDataBaseMgr.beginTransaction/?'+temp); inFunc();uex.exec('uexDataBaseMgr.endTransaction/?'+temp);\n};";
        }
        [JS appendString:methodJS];
    }];
    return JS;
}

@end
