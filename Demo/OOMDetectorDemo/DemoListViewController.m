//
//  DemoListViewController.m
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

#import "DemoListViewController.h"

@interface DemoListViewController ()

@property (nonatomic, retain) NSArray *dataArr;

@end

@implementation DemoListViewController

- (NSArray *)configDataArray
{
    return @[@"C数据类型内存泄漏引发内存暴增",
             @"OC对象内存泄漏(MRC)检查",
             @"大内存分配监控",
             @"模拟内存暴增引发crash",];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"OOMDetectorDemo";
    
    self.dataArr = [self configDataArray];
    self.view.backgroundColor = [UIColor whiteColor];
    self.tableView.rowHeight = 50;
}


#pragma mark - Table view data source and delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataArr.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ID = @"demoCellId";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ID];
    }
    cell.textLabel.text = [NSString stringWithFormat:@"%ld -- %@", indexPath.row, self.dataArr[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIViewController *vc = [NSClassFromString([NSString stringWithFormat:@"DemoViewController%ld", indexPath.row]) new];
    vc.title = self.dataArr[indexPath.row];
    [self.navigationController pushViewController:vc animated:YES];
}


@end
