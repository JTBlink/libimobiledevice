# MobileSync 能否获取联系人 - 代码仓库深度分析

## 分析日期
2025-12-12

## 一、代码仓库结构分析

### 1.1 MobileSync 实现文件
- **核心实现**: `src/mobilesync.c` (791行)
- **头文件**: `include/libimobiledevice/mobilesync.h`
- **内部头文件**: `src/mobilesync.h`
- **Python绑定**: `cython/mobilesync.pxi`

### 1.2 关键发现

✅ **libimobiledevice 完整实现了 MobileSync 协议**

从代码分析可以确认：

1. **协议完整性**
   - 实现了所有标准的 MobileSync 协议消息
   - 支持双向同步（设备→电脑、电脑→设备）
   - 支持三种同步类型（Fast/Slow/Reset）

2. **API 完整性**
   ```c
   // 核心API都已实现
   mobilesync_client_new()
   mobilesync_start()
   mobilesync_get_all_records_from_device()  // ✅ 获取所有记录
   mobilesync_get_changes_from_device()      // ✅ 获取变更
   mobilesync_receive_changes()              // ✅ 接收数据
   mobilesync_acknowledge_changes_from_device()
   mobilesync_finish()
   ```

3. **数据类支持**
   - 代码中使用 `"com.apple.Contacts"` 作为联系人数据类
   - 这是标准的 iOS 联系人数据类标识符

## 二、协议消息流程（从代码反推）

### 2.1 同步会话建立

```c
// src/mobilesync.c:136-260
mobilesync_start(client, "com.apple.Contacts", anchors, ...)
```

发送消息:
```
["SDMessageSyncDataClassWithDevice",
 "com.apple.Contacts",
 device_anchor,
 computer_anchor,
 computer_data_class_version,
 "___EmptyParameterString___"]
```

期望响应:
```
["SDMessageSynchronize", ..., sync_type, device_version]
```

### 2.2 请求联系人数据

```c
// src/mobilesync.c:347-350
mobilesync_get_all_records_from_device(client)
  -> mobilesync_get_records(client, "SDMessageGetAllRecordsFromDevice")
```

发送消息:
```
["SDMessageGetAllRecordsFromDevice",
 "com.apple.Contacts"]
```

### 2.3 接收联系人数据

```c
// src/mobilesync.c:357-422
mobilesync_receive_changes(client, &entities, &is_last_record, &actions)
```

接收消息格式:
```
[response_type, ..., entities, has_more_changes, actions]
```

其中 `entities` 是一个 **PLIST_DICT**，包含所有联系人数据。

## 三、联系人数据格式（从代码推断）

### 3.1 数据结构

```c
// entities 是一个字典，键是联系人ID，值是联系人详情
plist_t entities = {
    "contact_id_1": {
        // 联系人1的所有字段
    },
    "contact_id_2": {
        // 联系人2的所有字段
    },
    ...
}
```

### 3.2 字段名称问题 ⚠️

**关键发现**：代码中**没有对字段名称进行任何映射或转换**！

```c
// src/mobilesync.c:395-397
if (entities != NULL) {
    *entities = plist_copy(plist_array_get_item(msg, 2));
}
```

这意味着：
- **字段名完全由 iOS 设备决定**
- libimobiledevice **直接透传** iOS 返回的原始数据
- **没有字段名标准化或映射层**

## 四、问题根源分析

### 4.1 从日志看实际情况

**日志显示的字段**：
```xml
<dict>
    <key>first name</key>
    <string>珠江客服中心</string>
    
    <key>last name</key>
    <string>欧派橱柜安装</string>
    
    <key>notes</key>
    <string>...</string>
    
    <key>display as company</key>
    <string>person</string>
</dict>
```

**完全没有电话号码字段！**

### 4.2 三种可能性

#### 可能性 1: iOS 设备未返回电话号码 ✅ **最可能**

**证据**：
1. 代码显示数据是直接透传的
2. 日志中509个联系人都没有电话号码字段
3. 这种一致性说明不是个别联系人问题

**原因猜测**：
- iOS 隐私保护策略
- MobileSync 权限限制
- 设备端同步配置问题
- iOS 版本差异

#### 可能性 2: 字段名称不是预期的 ❌ 不太可能

因为日志显示：
- 有 `first name`、`last name` 等字段
- 这些字段名是小写+空格格式
- 电话号码字段应该也会出现（如果存在的话）

#### 可能性 3: 需要特殊请求参数 ⚠️ 有可能

查看代码中的 actions 参数：

```c
// src/mobilesync.c:753-783
void mobilesync_actions_add(plist_t actions, ...)
```

支持的 action keys:
- `SyncDeviceLinkEntityNamesKey` - 指定要同步的实体名称
- `SyncDeviceLinkAllRecordsOfPulledEntityTypeSentKey` - 布尔值

**可能需要通过 actions 参数指定要同步的字段？**

## 五、对比 iTunes 实现

### 5.1 iTunes 能做什么

iTunes 能够成功同步包括电话号码在内的完整联系人信息。

### 5.2 可能的差异

1. **版本协商**
   ```c
   // src/mobilesync.c:92
   device_link_service_version_exchange(dlclient, MSYNC_VERSION_INT1, MSYNC_VERSION_INT2)
   // MSYNC_VERSION_INT1 = 400
   // MSYNC_VERSION_INT2 = 100
   ```
   iTunes 可能使用不同的版本号？

2. **同步参数**
   iTunes 可能在 `mobilesync_start()` 或后续请求中传递了特殊参数

3. **授权/认证**
   iTunes 可能有额外的授权流程

## 六、验证方法

### 6.1 方法1: 抓包对比

```bash
# 抓取 iTunes 同步联系人的网络包
# 对比与 libimobiledevice 的差异
```

### 6.2 方法2: 添加详细日志

修改 `src/mobilesync.c`:

```c
// 在 mobilesync_receive_changes() 中
if (entities && plist_get_node_type(entities) == PLIST_DICT) {
    // 打印完整XML
    char* xml = NULL;
    uint32_t xml_len = 0;
    plist_to_xml(entities, &xml, &xml_len);
    
    debug_info("=== 完整联系人数据 ===");
    debug_info("%s", xml);
    debug_info("======================");
    
    free(xml);
    
    // 遍历所有字段
    plist_dict_iter iter = NULL;
    plist_dict_new_iter(entities, &iter);
    char* contact_id = NULL;
    plist_t contact_data = NULL;
    
    while (1) {
        plist_dict_next_item(entities, iter, &contact_id, &contact_data);
        if (!contact_id) break;
        
        debug_info("联系人 ID: %s", contact_id);
        
        if (plist_get_node_type(contact_data) == PLIST_DICT) {
            plist_dict_iter field_iter = NULL;
            plist_dict_new_iter(contact_data, &field_iter);
            char* field_name = NULL;
            plist_t field_value = NULL;
            
            debug_info("  可用字段:");
            while (1) {
                plist_dict_next_item(contact_data, field_iter, &field_name, &field_value);
                if (!field_name) break;
                
                plist_type type = plist_get_node_type(field_value);
                debug_info("    - '%s' (type: %d)", field_name, type);
                
                free(field_name);
            }
            free(field_iter);
        }
        
        free(contact_id);
    }
    free(iter);
}
```

### 6.3 方法3: 测试不同参数

```c
// 测试是否需要 actions 参数
plist_t actions = mobilesync_actions_new();

// 尝试添加实体名称
char* entity_names[] = {"Phone", "Email", "Address"};
mobilesync_actions_add(actions, 
    "SyncDeviceLinkEntityNamesKey", 
    entity_names, 
    3,
    NULL);

// 在 receive_changes 时传入
mobilesync_receive_changes(client, &entities, &is_last, &actions);
```

## 七、结论

### 7.1 MobileSync 能否获取联系人？

**✅ 理论上可以，代码完整实现了协议**

但实际情况是：
- ✅ 能获取联系人基本信息（姓名、备注等）
- ❌ **无法获取电话号码**（至少在当前配置下）

### 7.2 核心问题

**iOS 设备通过 MobileSync 返回的数据中不包含电话号码字段**

可能原因：
1. iOS 隐私保护限制
2. 需要特殊的同步配置或参数
3. 需要额外的权限或授权
4. libimobiledevice 的实现与 iTunes 有细微差异

### 7.3 建议

#### 短期方案
1. 添加详细日志，确认所有可用字段
2. 对比 iTunes 的网络通信
3. 尝试不同的参数组合

#### 长期方案
如果确认 MobileSync 无法获取电话号码：
1. 使用 **MobileBackup2** 作为备选（可以从备份中提取联系人）
2. 研究是否有其他 iOS 服务可以访问联系人
3. 考虑使用 iCloud API（需要用户授权）

## 八、代码证据总结

| 能力 | 状态 | 证据 |
|-----|------|------|
| 协议实现 | ✅ 完整 | `src/mobilesync.c` 791行完整实现 |
| 连接能力 | ✅ 支持 | `mobilesync_client_new()` |
| 同步会话 | ✅ 支持 | `mobilesync_start()` |
| 获取记录 | ✅ 支持 | `mobilesync_get_all_records_from_device()` |
| 接收数据 | ✅ 支持 | `mobilesync_receive_changes()` |
| 数据透传 | ✅ 确认 | 无字段映射，直接返回iOS数据 |
| 电话号码 | ❌ 缺失 | 日志显示509个联系人都无此字段 |

## 九、下一步行动

1. **立即**: 添加详细日志，打印所有可用字段
2. **短期**: 抓包对比 iTunes 的实现
3. **中期**: 尝试使用 MobileBackup2 替代方案
4. **长期**: 向 libimobiledevice 社区报告此问题