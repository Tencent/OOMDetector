//
//  ViewController.m
//  QQLeakDemo
//
//  Tencent is pleased to support the open source community by making OOMDetector available.
//  Copyright (C) 2017 THL A29 Limited, a Tencent company. All rights reserved.
//  Licensed under the MIT License (the "License"); you may not use this file except
//  in compliance with the License. You may obtain a copy of the License at
//
//  http://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//
#import "BaseDemoViewController.h"
#import "AppDelegate.h"

@import libOOMDetector;

@interface BaseDemoViewController ()

@property (nonatomic, strong) UIScrollView *contentView;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UIActivityIndicatorView *indicator;

@end

@implementation BaseDemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupViews];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onReceiveChunkMallocNoti:) name:kChunkMallocNoti object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self showIndicator:NO];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupViews
{
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIScrollView *contentView = [UIScrollView new];
    [self.view addSubview:contentView];
    self.contentView = contentView;
    
    UILabel *label = [UILabel new];
    label.textColor = [UIColor grayColor];
    label.font = [UIFont systemFontOfSize:15];
    label.layer.borderColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.6].CGColor;
    label.layer.borderWidth = 0.5;
    label.numberOfLines = 0;
    self.codeLabel = label;
    
    UIButton *runBtn = [[UIButton alloc] init];
    [runBtn setTitle:@"运行Demo代码" forState:UIControlStateNormal];
    [runBtn addTarget:self action:@selector(runDemoCode) forControlEvents:UIControlEventTouchUpInside];
    [runBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [runBtn setTitleColor:[[UIColor lightGrayColor] colorWithAlphaComponent:0.2] forState:UIControlStateHighlighted];
    runBtn.layer.cornerRadius = 20;
    runBtn.clipsToBounds = YES;
    runBtn.layer.borderWidth = 0.5;
    runBtn.layer.borderColor = label.layer.borderColor;
    self.runButton = runBtn;
    
    UIButton *checkLeakBtn = [[UIButton alloc] init];
    [checkLeakBtn setTitle:@"检测是否有内存泄漏" forState:UIControlStateNormal];
    [checkLeakBtn addTarget:self action:@selector(checkLeak) forControlEvents:UIControlEventTouchUpInside];
    [checkLeakBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [checkLeakBtn setTitleColor:[[UIColor lightGrayColor] colorWithAlphaComponent:0.6] forState:UIControlStateHighlighted];
    checkLeakBtn.layer.cornerRadius = 20;
    checkLeakBtn.clipsToBounds = YES;
    checkLeakBtn.layer.borderWidth = 0.5;
    checkLeakBtn.layer.borderColor = label.layer.borderColor;
    self.checkButton = checkLeakBtn;
    
    UILabel *resLabel = [UILabel new];
    resLabel.layer.borderColor = label.layer.borderColor;
    resLabel.layer.borderWidth = 0.5;
    resLabel.font = [UIFont systemFontOfSize:15];
    resLabel.numberOfLines = 0;
    self.resultLabel = resLabel;
    
    [contentView addSubview:label];
    [contentView addSubview:runBtn];
    [contentView addSubview:checkLeakBtn];
    [contentView addSubview:resLabel];
    
}

- (void)onReceiveChunkMallocNoti:(NSNotification *)noti
{
    
}

- (void)dealloc
{
    [self.indicator removeFromSuperview];
    self.indicator = nil;
    
    self.checkButton = nil;
    self.desLabel = nil;
    self.contentView = nil;
}

- (void)showIndicator:(BOOL)yn
{
    if (!self.indicator) {
        UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        indicator.color = [UIColor lightGrayColor];
        self.indicator = indicator;
        self.indicator.center = CGPointMake([UIScreen mainScreen].bounds.size.width * 0.5, [UIScreen mainScreen].bounds.size.height * 0.5);
    }
    self.indicator.hidden = !yn;
    if (yn) {
        [[UIApplication sharedApplication].keyWindow addSubview:self.indicator];
        [self.indicator startAnimating];
    } else {
        [self.indicator stopAnimating];
        [self.indicator removeFromSuperview];
    }
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    self.codeLabel.text = [NSString stringWithFormat:@"演示代码如下：\n\n%@", [self demoCodeText]];
    if ([self demoDescriptionString].length) {
        self.codeLabel.text = [NSString stringWithFormat:@"%@\n\nDemo介绍如下：\n%@", self.codeLabel.text, [self demoDescriptionString]];
    }
    
    CGFloat hMargin = 12.f;
    CGFloat vMargin = 30.f;
    CGFloat w = self.view.frame.size.width - hMargin * 2;
    
    CGFloat codeLabelH = [self.codeLabel.text boundingRectWithSize:CGSizeMake(w, MAXFLOAT) options:NSStringDrawingUsesFontLeading | NSStringDrawingUsesLineFragmentOrigin  attributes:@{NSFontAttributeName : self.codeLabel.font} context:nil].size.height;
    codeLabelH += 20;
    self.codeLabel.frame = CGRectMake(hMargin, vMargin, w, codeLabelH);
    
    self.runButton.frame = CGRectMake(hMargin, CGRectGetMaxY(self.codeLabel.frame) + vMargin, w, 40);
    
    self.checkButton.frame = CGRectMake(hMargin, CGRectGetMaxY(self.runButton.frame) + vMargin, w, 40);
    if (self.isOOMDemo) {
        self.checkButton.hidden = YES;
        self.checkButton.frame = self.runButton.frame;
    }
    
    CGFloat resultLabelH = [self.resultLabel.text boundingRectWithSize:CGSizeMake(w, MAXFLOAT) options:NSStringDrawingUsesFontLeading | NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName : self.resultLabel.font} context:nil].size.height;
    resultLabelH += 20;
    self.resultLabel.frame = CGRectMake(hMargin, CGRectGetMaxY(self.checkButton.frame) + vMargin, w, MAX(resultLabelH, 150));
    
    self.contentView.frame = self.view.bounds;
    
    self.contentView.contentSize = CGSizeMake(self.contentView.frame.size.width, CGRectGetMaxY(self.resultLabel.frame) + vMargin);
    
}

- (void)runDemoCode
{
    // 子类重写此方法填充演示代码
}

- (NSString *)demoCodeText
{
    // 子类重写此方法填充演示代码
    return nil;
}

- (NSString *)demoDescriptionString
{
    // 子类重写此方法填充demo介绍
    return @"";
}

- (void)checkLeak
{
#if TARGET_IPHONE_SIMULATOR
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"目前尚不支持在模拟器上进行内存泄漏检测，请切换至真机运行。" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:action];
    [self presentViewController:alert animated:YES completion:nil];
#else
    if (![[OOMDetector getInstance].currentLeakChecker isStackLogging]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"你尚未开启内存泄漏监控" message:@"如需开启内存泄漏监控，请使用OOMDetector类提供的相关api进行设置。" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:action];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.resultLabel.text = @"";
    
    if (!self.isOOMDemo) {
        [self showIndicator:YES];
        [[OOMDetector getInstance] executeLeakCheck:^(NSString *leakStack, size_t total_num){
            [self setupResLabel:leakStack];
            [self showIndicator:NO];
        }];
    }
#endif
}

- (void)setupResLabel:(NSString *)res
{
    self.resultLabel.text = [NSString stringWithFormat:@"检测结果如下：\n\n%@", res];
    
    [self.view setNeedsLayout];
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
}

- (NSString *)formatDemoString:(NSString *)string
{
    string = [string stringByReplacingOccurrencesOfString:@"; }" withString:@"; §}\n§"];

    NSRegularExpression *reg0 = [NSRegularExpression regularExpressionWithPattern:@"; ?" options:0 error:nil];
    string = [reg0 stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:@";\n§"];
    
    NSError *err;
    
    NSRegularExpression *reg1 = [NSRegularExpression regularExpressionWithPattern:@"\\{ " options:0 error:&err];
    string = [reg1 stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:@"{\n§"];
    
    NSRegularExpression *reg2 = [NSRegularExpression regularExpressionWithPattern:@"\\}\\);" options:0 error:&err];
    string = [reg2 stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:@"§});"];
    
    NSRegularExpression *reg3 = [NSRegularExpression regularExpressionWithPattern:@"\\^\\{" options:0 error:&err];
    string = [reg3 stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:@"^{\n§"];

    string = [string stringByReplacingOccurrencesOfString:@"§§" withString:@"§"];
    
    NSArray *components = [string componentsSeparatedByString:@"§"];
    __block int level = 0;
    NSString *space = @"    ";
    NSMutableString *res = [NSMutableString string];
    [components enumerateObjectsUsingBlock:^(NSString *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.length > 0) {
            if ([obj hasSuffix:@"}"] || [obj hasSuffix:@"}\n"] || [obj hasSuffix:@"});\n"]) {
                --level;
            }
            
            for (int i = 0; i < level; i++) {
                [res appendString:space];
            }
            [res appendString:obj];
            
            if ([obj hasSuffix:@"{\n"]) {
                ++level;
            }
        }
    }];
    return res;
}

@end
