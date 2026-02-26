# MobileSync 联系人字段映射问题分析

## 问题描述

从iOS设备通过 MobileSync 协议获取联系人时，**无法获取到电话号码**数据。

## 实际数据格式

### 从日志中观察到的实际字段名（iOS返回）：

```xml
<dict>
    <key>display as company</key>
    <string>person</string>
    
    <key>com.apple.syncservices.RecordEntityName</key>
    <string>com.apple.contacts.Contact</string>
    
    <key>notes</key>
    <string>珠江客服咨询...</string>
    
    <key>first name</key>
    <string>珠江客服中心</string>
    
    <key>last name</key>
    <string>欧派橱柜安装</string>
</dict>
```

### 关键发现

1. **字段名格式**: 实际字段名是 **小写 + 空格分隔**（如 `first name`）
2. **缺失字段**: 没有看到任何电话号码相关的字段
3. **文档错误**: 文档中描述的字段名（如 `First`、`Phone`）与实际不符

## 可能的原因

### 1. 字段名称映射错误 ❌

文档中的字段名（`Phone`、`Email`）可能需要映射为实际的字段名。

**预期的电话号码字段名可能是：**
- `phone` (小写)
- `phone numbers` (小写 + 空格)
- `phones` (复数形式)

### 2. iOS 设备没有返回电话号码数据 ✅ **最可能**

根据日志显示，设备返回的联系人数据本身就**不包含电话号码字段**。这可能是因为：

- **权限问题**: MobileSync 协议可能没有权限访问电话号码
- **隐私保护**: iOS 可能限制了电话号码的同步
- **同步配置**: 需要特定的配置或参数才能同步电话号码
- **iOS版本差异**: 不同iOS版本的字段结构可能不同

### 3. 需要额外的请求参数

可能需要在同步请求中指定额外的参数来获取完整的联系人信息。

## 解决方案

### 方案 1: 检查实际可用的字段 ✅ 推荐

修改代码，打印所有收到的字段名，找出电话号码的实际字段名：

```c
// 在处理联系人数据时
plist_dict_iter iter = NULL;
plist_dict_new_iter(contact_dict, &iter);

char* key = NULL;
plist_t val = NULL;

printf("联系人的所有字段:\n");
while (1) {
    plist_dict_next_item(contact_dict, iter, &key, &val);
    if (!key) break;
    
    plist_type type = plist_get_node_type(val);
    printf("  字段名: '%s', 类型: %d\n", key, type);
    
    free(key);
    key = NULL;
}
free(iter);
```

### 方案 2: 使用正确的字段名列表

基于实际观察，尝试以下字段名获取电话号码：

```c
const char* phone_field_names[] = {
    "phone",
    "phone numbers",
    "phones",
    "Phone",
    "Phone Numbers",
    "Phones",
    "mobile",
    "Mobile",
    "cell",
    "Cell",
    NULL
};

// 遍历尝试每个可能的字段名
for (int i = 0; phone_field_names[i] != NULL; i++) {
    plist_t phone_node = plist_dict_get_item(contact_dict, phone_field_names[i]);
    if (phone_node) {
        printf("找到电话号码字段: %s\n", phone_field_names[i]);
        // 处理电话号码数据
        break;
    }
}
```

### 方案 3: 检查 SyncServices 映射

iOS 的 SyncServices 框架可能使用了特定的字段映射规则。根据：
```
com.apple.syncservices.RecordEntityName = com.apple.contacts.Contact
```

可能需要查阅 SyncServices 的字段映射文档或反向工程实际的映射关系。

### 方案 4: 使用 AddressBook 数据类

尝试使用不同的数据类名称：

```c
// 不使用 "com.apple.Contacts"
// 尝试其他可能的数据类名称：
const char* data_class_names[] = {
    "com.apple.Contacts",
    "com.apple.contacts",
    "Contacts",
    "contacts",
    "AddressBook",
    "com.apple.AddressBook",
    NULL
};
```

### 方案 5: 对比 iTunes 的实现

iTunes 能够正确同步通讯录，可以：
1. 抓包分析 iTunes 的 MobileSync 通信
2. 查看 iTunes 发送的参数和请求格式
3. 对比返回数据的结构

## 验证方法

### 1. 添加详细日志

在 `mobilesync_receive_changes` 之后，详细打印所有字段：

```c
if (entities && plist_get_node_type(entities) == PLIST_DICT) {
    // 打印完整的 plist 结构
    char* xml = NULL;
    uint32_t xml_len = 0;
    plist_to_xml(entities, &xml, &xml_len);
    printf("完整联系人数据:\n%s\n", xml);
    free(xml);
}
```

### 2. 测试不同的设备和iOS版本

在不同设备上测试，确认是否是设备特定问题。

### 3. 检查设备端的同步设置

在iOS设备上检查"设置 > Apple ID > iCloud"中的通讯录同步设置。

## 下一步行动

1. ✅ **首要任务**: 修改代码打印所有可用字段，找出电话号码的实际字段名
2. 检查是否需要特定的同步配置或权限
3. 参考 iTunes 或其他成功案例的实现
4. 如果确认 iOS 不返回电话号码，考虑使用备用方案（如 MobileBackup2）

## 参考资料

- Apple SyncServices Programming Guide (已废弃)
- libimobiledevice 源代码: `src/mobilesync.c`
- 相关 issue 和讨论