# MobileSync 通讯录获取分析

## 一、MobileSync 服务概述

### 1.1 服务定义
- **服务名称**: `com.apple.mobilesync`
- **协议基础**: DeviceLink Service Protocol
- **版本号**: 400/100
- **功能**: iOS 设备与计算机之间的双向数据同步

### 1.2 支持的数据类（Data Classes）
MobileSync 支持以下数据类的同步：

1. **`com.apple.Contacts`** - 通讯录 ✅
2. **`com.apple.Calendars`** - 日历
3. **`com.apple.Notes`** - 备忘录
4. **`com.apple.Bookmarks`** - 书签

## 二、能否用 MobileSync 获取通讯录？

### ✅ **答案：可以！**

MobileSync 专门设计用于同步通讯录等结构化数据，完全支持通讯录的获取和同步。

### 2.1 优势
1. **专用协议**: 专门为通讯录等结构化数据设计
2. **双向同步**: 支持设备→电脑和电脑→设备的双向数据传输
3. **增量同步**: 支持快速同步（仅同步变更）
4. **结构化数据**: 返回标准的 plist 字典格式通讯录数据
5. **无需文件系统权限**: 不依赖 AFC 或文件备份

### 2.2 与 MobileBackup2 的对比

| 特性 | MobileSync | MobileBackup2 |
|-----|-----------|--------------|
| **用途** | 结构化数据同步 | 完整设备备份 |
| **通讯录支持** | ✅ 原生支持 | ⚠️ 需要通过备份提取 |
| **数据格式** | 结构化 plist 字典 | 备份文件（需要解析） |
| **同步方式** | 双向、增量 | 单向备份 |
| **权限要求** | 较低 | 较高（需要备份权限） |
| **实时性** | 高（直接读取） | 低（需要完整备份） |

## 三、MobileSync 通讯录获取流程

### 3.1 完整流程图

```
[计算机]                                    [iOS设备]
   |                                           |
   |-- 1. lockdownd_start_service ----------->|
   |   (com.apple.mobilesync)                 |
   |                                           |
   |<- 2. Service Descriptor (port) ----------|
   |                                           |
   |-- 3. mobilesync_client_new -------------->|
   |   (建立连接 + 版本协商)                   |
   |                                           |
   |<- 4. Version Exchange OK ----------------|
   |                                           |
   |-- 5. mobilesync_start ------------------->|
   |   ["SDMessageSyncDataClassWithDevice",   |
   |    "com.apple.Contacts",                 |
   |    device_anchor,                        |
   |    computer_anchor,                      |
   |    version]                              |
   |                                           |
   |<- 6. Sync Type Response -----------------|
   |   ["SDMessageSynchronize",               |
   |    ...,                                  |
   |    "SDSyncTypeFast/Slow/Reset"]         |
   |                                           |
   |-- 7. mobilesync_get_all_records -------->|
   |   或 mobilesync_get_changes              |
   |                                           |
   |<- 8. mobilesync_receive_changes ---------|
   |   [contacts entities dict]               |
   |                                           |
   |-- 9. mobilesync_acknowledge ------------->|
   |                                           |
   |-- 10. mobilesync_finish ----------------->|
   |                                           |
   |<- 11. Session Finished ------------------|
   |                                           |
   |-- 12. mobilesync_client_free ------------>|
```

### 3.2 关键 API 调用序列

```c
// 1. 连接到 MobileSync 服务
mobilesync_client_t client = NULL;
lockdownd_service_descriptor_t service = NULL;

lockdownd_start_service(lockdown, MOBILESYNC_SERVICE_NAME, &service);
mobilesync_client_new(device, service, &client);

// 2. 创建锚点（用于跟踪同步状态）
mobilesync_anchors_t anchors = mobilesync_anchors_new(
    NULL,           // device_anchor (NULL = first sync)
    "InitialSync"   // computer_anchor
);

// 3. 启动通讯录同步会话
mobilesync_sync_type_t sync_type;
uint64_t device_version;
char* error = NULL;

mobilesync_start(
    client,
    "com.apple.Contacts",  // 数据类：通讯录
    anchors,
    1,                     // computer_data_class_version
    &sync_type,
    &device_version,
    &error
);

// 4. 请求所有通讯录记录
mobilesync_get_all_records_from_device(client);

// 5. 接收通讯录数据
plist_t entities = NULL;
uint8_t is_last = 0;
plist_t actions = NULL;

while (!is_last) {
    mobilesync_receive_changes(client, &entities, &is_last, &actions);
    
    // 处理 entities 字典中的通讯录数据
    // entities 格式: {"contact_id": {...contact_data...}, ...}
    
    plist_free(entities);
    plist_free(actions);
}

// 6. 确认接收
mobilesync_acknowledge_changes_from_device(client);

// 7. 结束同步会话
mobilesync_finish(client);

// 8. 清理
mobilesync_anchors_free(anchors);
mobilesync_client_free(client);
```

## 四、通讯录数据格式

### 4.1 Entity 字典结构

```xml
<dict>
    <key>contact_id_1</key>
    <dict>
        <key>First</key>
        <string>张</string>
        
        <key>Last</key>
        <string>三</string>
        
        <key>Display</key>
        <string>张三</string>
        
        <key>Phone</key>
        <array>
            <dict>
                <key>value</key>
                <string>13800138000</string>
                <key>label</key>
                <string>mobile</string>
            </dict>
        </array>
        
        <key>Email</key>
        <array>
            <dict>
                <key>value</key>
                <string>zhangsan@example.com</string>
                <key>label</key>
                <string>work</string>
            </dict>
        </array>
        
        <key>com.apple.syncservices.RecordEntityName</key>
        <string>com.apple.contacts.Contact</string>
    </dict>
    
    <key>contact_id_2</key>
    <dict>
        <!-- 下一个联系人数据 -->
    </dict>
</dict>
```

### 4.2 常见字段

| 字段名 | 类型 | 说明 |
|-------|------|------|
| `First` | string | 名 |
| `Last` | string | 姓 |
| `Middle` | string | 中间名 |
| `Display` | string | 显示名称 |
| `Nickname` | string | 昵称 |
| `Organization` | string | 组织/公司 |
| `Phone` | array | 电话号码列表 |
| `Email` | array | 电子邮件列表 |
| `Address` | array | 地址列表 |
| `Birthday` | date | 生日 |
| `Note` | string | 备注 |

## 五、同步类型详解

### 5.1 Fast Sync（快速同步）
```c
if (sync_type == MOBILESYNC_SYNC_TYPE_FAST) {
    // 仅同步自上次同步后的变更
    mobilesync_get_changes_from_device(client);
}
```
- **使用场景**: 已经完成过初次同步
- **优点**: 速度快，数据量小
- **要求**: 必须保存有效的 device_anchor

### 5.2 Slow Sync（慢速同步）
```c
if (sync_type == MOBILESYNC_SYNC_TYPE_SLOW) {
    // 同步所有数据
    mobilesync_get_all_records_from_device(client);
}
```
- **使用场景**: 首次同步或锚点失效
- **特点**: 传输所有通讯录数据
- **耗时**: 较长，取决于通讯录数量

### 5.3 Reset Sync（重置同步）
```c
if (sync_type == MOBILESYNC_SYNC_TYPE_RESET) {
    // 清除计算机上的所有数据，重新同步
    mobilesync_clear_all_records_on_device(client);
    mobilesync_get_all_records_from_device(client);
}
```
- **使用场景**: 数据冲突或需要完全重置
- **注意**: 会清除计算机端的所有通讯录数据

## 六、锚点（Anchor）机制

### 6.1 锚点作用
锚点用于跟踪同步状态，实现增量同步：

```c
typedef struct {
    char *device_anchor;    // 设备端的同步状态标识
    char *computer_anchor;  // 计算机端的同步状态标识
} mobilesync_anchors;
```

### 6.2 锚点使用流程

**首次同步**:
```c
// device_anchor = NULL (表示首次同步)
anchors = mobilesync_anchors_new(NULL, "Computer_2024-12-12");

mobilesync_start(client, "com.apple.Contacts", anchors, ...);
// 设备返回新的 device_anchor: "Device_12345"
```

**后续同步**:
```c
// 使用上次同步返回的 device_anchor
anchors = mobilesync_anchors_new(
    "Device_12345",           // 上次同步的设备锚点
    "Computer_2024-12-13"     // 新的计算机锚点
);

mobilesync_start(client, "com.apple.Contacts", anchors, ...);
// 如果锚点有效，设备返回 FAST sync
// 如果锚点无效，设备返回 SLOW sync 并提供新锚点
```

### 6.3 锚点持久化
```c
// 同步完成后，保存 device_anchor 用于下次同步
char* new_device_anchor = NULL;
// 从 mobilesync_start 的响应中获取
// 保存到本地配置文件或数据库
```

## 七、错误处理

### 7.1 常见错误

| 错误码 | 错误名 | 原因 | 解决方案 |
|-------|--------|------|---------|
| -7 | `SYNC_REFUSED` | 设备拒绝同步 | 检查设备设置，可能需要用户授权 |
| -8 | `CANCELLED` | 设备取消会话 | 检查错误描述，可能是权限问题 |
| -6 | `BAD_VERSION` | 版本不兼容 | 更新库版本 |
| -9 | `WRONG_DIRECTION` | 同步方向错误 | 检查 API 调用顺序 |
| -10 | `NOT_READY` | 设备未就绪 | 等待设备响应或重试 |

### 7.2 错误处理示例

```c
mobilesync_error_t err;
char* error_desc = NULL;

err = mobilesync_start(client, "com.apple.Contacts", 
                      anchors, 1, &sync_type, 
                      &device_version, &error_desc);

if (err == MOBILESYNC_E_SYNC_REFUSED) {
    printf("设备拒绝同步: %s\n", error_desc);
    // 可能需要用户在设备上授权
} else if (err == MOBILESYNC_E_CANCELLED) {
    printf("同步被取消: %s\n", error_desc);
} else if (err != MOBILESYNC_E_SUCCESS) {
    printf("同步启动失败: %d\n", err);
}

if (error_desc) {
    free(error_desc);
}
```

## 八、实际应用示例

### 8.1 简单通讯录读取器

```c
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/mobilesync.h>

void read_contacts(const char* udid) {
    idevice_t device = NULL;
    lockdownd_client_t lockdown = NULL;
    mobilesync_client_t sync_client = NULL;
    lockdownd_service_descriptor_t service = NULL;
    
    // 1. 连接设备
    if (idevice_new(&device, udid) != IDEVICE_E_SUCCESS) {
        printf("无法连接设备\n");
        return;
    }
    
    // 2. 启动 lockdown 客户端
    if (lockdownd_client_new_with_handshake(device, &lockdown, "ContactReader") 
        != LOCKDOWN_E_SUCCESS) {
        printf("lockdown 握手失败\n");
        goto cleanup;
    }
    
    // 3. 启动 MobileSync 服务
    if (lockdownd_start_service(lockdown, MOBILESYNC_SERVICE_NAME, &service) 
        != LOCKDOWN_E_SUCCESS) {
        printf("无法启动 MobileSync 服务\n");
        goto cleanup;
    }
    
    // 4. 创建 MobileSync 客户端
    if (mobilesync_client_new(device, service, &sync_client) 
        != MOBILESYNC_E_SUCCESS) {
        printf("无法创建 MobileSync 客户端\n");
        goto cleanup;
    }
    
    // 5. 准备锚点
    mobilesync_anchors_t anchors = mobilesync_anchors_new(NULL, "InitialSync");
    
    // 6. 启动同步
    mobilesync_sync_type_t sync_type;
    uint64_t device_version;
    char* error = NULL;
    
    if (mobilesync_start(sync_client, "com.apple.Contacts", 
                        anchors, 1, &sync_type, 
                        &device_version, &error) 
        != MOBILESYNC_E_SUCCESS) {
        printf("启动同步失败: %s\n", error ? error : "未知错误");
        goto cleanup;
    }
    
    printf("同步类型: %d, 设备版本: %llu\n", sync_type, device_version);
    
    // 7. 请求所有通讯录
    mobilesync_get_all_records_from_device(sync_client);
    
    // 8. 接收通讯录数据
    plist_t entities = NULL;
    uint8_t is_last = 0;
    plist_t actions = NULL;
    int total_contacts = 0;
    
    while (!is_last) {
        if (mobilesync_receive_changes(sync_client, &entities, 
                                      &is_last, &actions) 
            == MOBILESYNC_E_SUCCESS) {
            
            if (entities && plist_get_node_type(entities) == PLIST_DICT) {
                uint32_t count = plist_dict_get_size(entities);
                total_contacts += count;
                
                printf("收到 %u 个联系人\n", count);
                
                // 遍历联系人
                plist_dict_iter iter = NULL;
                plist_dict_new_iter(entities, &iter);
                
                char* key = NULL;
                plist_t val = NULL;
                
                while (1) {
                    plist_dict_next_item(entities, iter, &key, &val);
                    if (!key || !val) break;
                    
                    // 提取联系人信息
                    plist_t name_node = plist_dict_get_item(val, "Display");
                    if (name_node) {
                        char* name = NULL;
                        plist_get_string_val(name_node, &name);
                        printf("  - %s (ID: %s)\n", name, key);
                        free(name);
                    }
                    
                    free(key);
                    key = NULL;
                }
                
                free(iter);
            }
            
            if (entities) plist_free(entities);
            if (actions) plist_free(actions);
        }
    }
    
    printf("总共读取 %d 个联系人\n", total_contacts);
    
    // 9. 确认接收
    mobilesync_acknowledge_changes_from_device(sync_client);
    
    // 10. 结束同步
    mobilesync_finish(sync_client);
    
cleanup:
    if (anchors) mobilesync_anchors_free(anchors);
    if (sync_client) mobilesync_client_free(sync_client);
    if (service) lockdownd_service_descriptor_free(service);
    if (lockdown) lockdownd_client_free(lockdown);
    if (device) idevice_free(device);
    if (error) free(error);
}
```

## 九、最佳实践

### 9.1 性能优化
1. **使用增量同步**: 保存 device_anchor，后续同步使用 FAST sync
2. **批量处理**: 一次性处理接收到的所有联系人，避免频繁 I/O
3. **异步处理**: 在后台线程执行同步操作

### 9.2 数据管理
1. **本地缓存**: 保存同步的通讯录数据到本地数据库
2. **版本控制**: 记录 device_data_class_version 用于冲突检测
3. **去重处理**: 根据联系人 ID 去重

### 9.3 错误恢复
1. **重试机制**: 网络错误时自动重试
2. **降级策略**: FAST sync 失败时降级为 SLOW sync
3. **日志记录**: 详细记录同步过程和错误

## 十、总结

### 10.1 MobileSync vs 其他方案

| 方案 | 优点 | 缺点 | 适用场景 |
|-----|------|------|---------|
| **MobileSync** | 专用协议、结构化数据、双向同步 | 需要设备授权 | 实时通讯录同步 |
| **MobileBackup2** | 完整备份、无需特殊授权 | 数据量大、需要解析 | 完整设备备份 |
| **AFC (文件访问)** | 直接访问文件系统 | 需要越狱或特殊权限 | 开发调试 |

### 10.2 建议
对于**通讯录获取**需求：
- ✅ **推荐使用 MobileSync**: 专门设计用于此目的，API 简单，数据结构化
- ⚠️ **避免使用 MobileBackup2**: 过于复杂，需要完整备份流程
- ❌ **不建议使用 AFC**: 权限限制严格，不适合生产环境

### 10.3 项目集成
libimobiledevice 项目已完整实现 MobileSync 协议：
- 核心实现: [`src/mobilesync.c`](../src/mobilesync.c)
- 公共头文件: [`include/libimobiledevice/mobilesync.h`](../include/libimobiledevice/mobilesync.h)
- Python 绑定: [`cython/mobilesync.pxi`](../cython/mobilesync.pxi)

可直接使用这些 API 实现通讯录的读取和同步功能。