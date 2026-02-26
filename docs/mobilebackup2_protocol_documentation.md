# MobileBackup2 通信协议详细文档

## 目录
1. [协议概述](#协议概述)
2. [协议层次结构](#协议层次结构)
3. [通信流程](#通信流程)
4. [消息格式](#消息格式)
5. [文件传输协议](#文件传输协议)
6. [Status.plist 机制](#statusplist-机制)
7. [代码示例](#代码示例)
8. [常见问题](#常见问题)

---

## 协议概述

MobileBackup2 是 iOS 4+ 设备的备份和恢复服务协议，基于 DeviceLink 服务实现。该协议支持：
- 完整备份和增量备份
- 备份加密
- 选择性恢复
- 云备份管理

### 关键特性
- **服务名称**: `com.apple.mobilebackup2`
- **协议版本**: 2.0 - 2.1
- **传输层**: SSL/TLS 加密
- **数据格式**: plist (XML/Binary)

---

## 协议层次结构

```
┌─────────────────────────────────────┐
│    MobileBackup2 Application        │  应用层
├─────────────────────────────────────┤
│      DeviceLink Service             │  协议层
├─────────────────────────────────────┤
│   PropertyList Service (SSL/TLS)    │  传输层
├─────────────────────────────────────┤
│        USB/Network Transport        │  连接层
└─────────────────────────────────────┘
```

### 代码常量定义

```c
// 文件传输代码 (tools/idevicebackup2.c:70-73)
#define CODE_SUCCESS 0x00        // 操作成功
#define CODE_ERROR_LOCAL 0x06    // 本地错误
#define CODE_ERROR_REMOTE 0x0b   // 远程错误
#define CODE_FILE_DATA 0x0c      // 文件数据块
```

---

## 通信流程

### 1. 连接建立

```
Host                                Device
 |                                     |
 |------ lockdownd_start_service ---->|
 |<----- service_descriptor ----------|
 |                                     |
 |------ device_link_service_new ----->|
 |<----- connection established -------|
```

### 2. 版本协商

```c
// 发送版本信息 (src/mobilebackup2.c:274-289)
mobilebackup2_version_exchange(client, local_versions[], count, &remote_version)

消息格式:
{
    "MessageName": "Hello",
    "SupportedProtocolVersions": [2.0, 2.1]
}

响应格式:
{
    "MessageName": "Response",
    "ErrorCode": 0,
    "ProtocolVersion": 2.1
}
```

### 3. 备份请求

```c
// 发送备份请求 (src/mobilebackup2.c:332-361)
mobilebackup2_send_request(client, "Backup", target_id, source_id, options)

选项字典:
{
    "TargetIdentifier": "00008110-000664261A83801E",
    "SourceIdentifier": "00008110-000664261A83801E",
    "Options": {
        "ForceFullBackup": true,
        "BackupComputerBasePathOverride": "/path/to/backup",
        "Sources": ["HomeDomain", "AppDomain"]
    }
}
```

### 4. 消息处理循环

```c
// 主处理循环 (tools/idevicebackup2.c:2288-2400)
do {
    mobilebackup2_receive_message(mobilebackup2, &message, &dlmsg);
    
    if (!strcmp(dlmsg, "DLMessageDownloadFiles")) {
        // 设备请求从主机下载文件
        mb2_handle_send_files(mobilebackup2, message, backup_directory);
    }
    else if (!strcmp(dlmsg, "DLMessageUploadFiles")) {
        // 设备上传文件到主机
        mb2_handle_receive_files(mobilebackup2, message, backup_directory);
    }
    else if (!strcmp(dlmsg, "DLMessageProcessMessage")) {
        // 处理状态消息
        handle_process_message(message);
    }
    else if (!strcmp(dlmsg, "DLMessageDisconnect")) {
        // 断开连接
        break;
    }
} while (!quit_flag);
```

---

## 消息格式

### DeviceLink 消息结构

所有 MobileBackup2 消息都封装在 DeviceLink 消息中：

```xml
<plist version="1.0">
<array>
    <string>DLMessage[MessageType]</string>
    <!-- 其他参数 -->
</array>
</plist>
```

### 主要消息类型

#### 1. DLMessageDownloadFiles

设备请求从主机下载文件：

```xml
<array>
    <string>DLMessageDownloadFiles</string>
    <array>
        <string>00008110-000664261A83801E/Status.plist</string>
        <string>00008110-000664261A83801E/Info.plist</string>
    </array>
    <real>0.0</real>  <!-- 进度 -->
    <real>100.0</real> <!-- 总进度 -->
</array>
```

#### 2. DLMessageUploadFiles

设备上传文件到主机：

```xml
<array>
    <string>DLMessageUploadFiles</string>
    <real>0.0</real>  <!-- 进度 -->
    <integer>1024</integer> <!-- 总大小 -->
</array>
```

#### 3. DLMessageProcessMessage

状态更新消息：

```xml
<array>
    <string>DLMessageProcessMessage</string>
    <dict>
        <key>MessageName</key>
        <string>Response</string>
        <key>ErrorCode</key>
        <integer>0</integer>
        <key>BackupState</key>
        <string>Finished</string>
    </dict>
</array>
```

#### 4. DLMessageStatusResponse

状态响应消息：

```c
// 发送状态响应 (src/mobilebackup2.c:363-386)
mobilebackup2_send_status_response(client, status_code, status1, status2)

<array>
    <string>DLMessageStatusResponse</string>
    <integer>0</integer>  <!-- 状态码: 0=成功, -13=多状态 -->
    <string>___EmptyParameterString___</string> <!-- 状态描述 -->
    <dict>
        <!-- 状态详情 -->
    </dict>
</array>
```

---

## 文件传输协议

### 发送文件 (主机 → 设备)

#### 协议格式

```
每个文件的传输格式:
┌────────────────┬───────────┬──────────────┐
│  4字节长度(BE) │ 1字节代码 │   数据块      │
└────────────────┴───────────┴──────────────┘

代码值:
- 0x0c (CODE_FILE_DATA): 文件数据块
- 0x00 (CODE_SUCCESS): 文件传输成功
- 0x06 (CODE_ERROR_LOCAL): 本地错误
```

#### 实现示例

```c
// 发送单个文件 (tools/idevicebackup2.c:820-920)
static int mb2_handle_send_file(mobilebackup2_client_t mobilebackup2, 
                                 const char *backup_dir, 
                                 const char *path, 
                                 plist_t *errplist)
{
    FILE *f = fopen(localfile, "rb");
    
    // 1. 发送文件数据块
    do {
        // 读取数据
        size_t r = fread(buf, 1, sizeof(buf), f);
        
        // 发送长度帧 (4字节BE长度 + 1字节代码)
        nlen = htobe32(r + 1);
        memcpy(buf_out, &nlen, 4);
        buf_out[4] = CODE_FILE_DATA;
        mobilebackup2_send_raw(mobilebackup2, buf_out, 5, &bytes);
        
        // 发送数据
        mobilebackup2_send_raw(mobilebackup2, buf, r, &bytes);
        
        sent += r;
    } while (sent < total);
    
    // 2. 发送成功标记
    nlen = htobe32(1);
    memcpy(buf, &nlen, 4);
    buf[4] = CODE_SUCCESS;
    mobilebackup2_send_raw(mobilebackup2, buf, 5, &bytes);
    
    return 0;
}
```

#### 批量发送流程

```c
// 处理文件下载请求 (tools/idevicebackup2.c:922-965)
static void mb2_handle_send_files(mobilebackup2_client_t mobilebackup2, 
                                   plist_t message, 
                                   const char *backup_dir)
{
    plist_t files = plist_array_get_item(message, 1);
    uint32_t cnt = plist_array_get_size(files);
    
    // 1. 逐个发送文件
    for (i = 0; i < cnt; i++) {
        char *str = NULL;
        plist_get_string_val(plist_array_get_item(files, i), &str);
        
        if (mb2_handle_send_file(mobilebackup2, backup_dir, str, &errplist) < 0) {
            break;
        }
        free(str);
    }
    
    // 2. 发送终止标记 (4字节0)
    uint32_t zero = 0;
    mobilebackup2_send_raw(mobilebackup2, (char*)&zero, 4, &sent);
    
    // 3. 发送状态响应
    if (!errplist) {
        plist_t emptydict = plist_new_dict();
        mobilebackup2_send_status_response(mobilebackup2, 0, NULL, emptydict);
        plist_free(emptydict);
    } else {
        mobilebackup2_send_status_response(mobilebackup2, -13, "Multi status", errplist);
        plist_free(errplist);
    }
}
```

### 接收文件 (设备 → 主机)

#### 协议格式

```
文件接收流程:
1. 接收4字节BE长度 → 目录名长度
2. 接收目录名
3. 接收4字节BE长度 → 文件名长度
4. 接收文件名
5. 循环接收数据块:
   - 接收4字节BE长度
   - 接收1字节代码
   - 如果代码是 CODE_FILE_DATA: 接收数据块
   - 如果代码是 CODE_SUCCESS: 文件结束
   - 如果长度为0: 所有文件结束
```

#### 实现示例

```c
// 接收文件名 (tools/idevicebackup2.c:967-1013)
static int mb2_receive_filename(mobilebackup2_client_t mobilebackup2, char** filename)
{
    uint32_t nlen = 0;
    uint32_t rlen = 0;
    
    // 1. 接收长度
    mobilebackup2_receive_raw(mobilebackup2, (char*)&nlen, 4, &rlen);
    nlen = be32toh(nlen);
    
    // 2. 检查结束标记
    if (nlen == 0 && rlen == 4) {
        return 0;  // 没有更多文件
    }
    
    // 3. 接收文件名
    *filename = (char*)malloc(nlen + 1);
    mobilebackup2_receive_raw(mobilebackup2, *filename, nlen, &rlen);
    (*filename)[rlen] = 0;
    
    return nlen;
}

// 接收文件数据 (tools/idevicebackup2.c:1015-1183)
static int mb2_handle_receive_files(mobilebackup2_client_t mobilebackup2,
                                     plist_t message,
                                     const char *backup_dir)
{
    char *fname = NULL;
    char *dname = NULL;
    FILE *f = NULL;
    
    do {
        // 1. 接收目录名
        if (mb2_receive_filename(mobilebackup2, &dname) == 0) break;
        
        // 2. 接收文件名
        if (mb2_receive_filename(mobilebackup2, &fname) == 0) break;
        
        // 3. 打开文件准备写入
        char *bname = string_build_path(backup_dir, fname, NULL);
        f = fopen(bname, "wb");
        
        // 4. 循环接收数据块
        do {
            // 接收长度
            uint32_t nlen = 0;
            mobilebackup2_receive_raw(mobilebackup2, (char*)&nlen, 4, &r);
            nlen = be32toh(nlen);
            
            if (nlen == 0) break;  // 结束标记
            
            // 接收代码
            char code = 0;
            mobilebackup2_receive_raw(mobilebackup2, &code, 1, &r);
            
            if (code == CODE_FILE_DATA) {
                // 接收并写入数据
                uint32_t blocksize = nlen - 1;
                while (bdone < blocksize) {
                    mobilebackup2_receive_raw(mobilebackup2, buf, rlen, &r);
                    fwrite(buf, 1, r, f);
                    bdone += r;
                }
            } else if (code == CODE_SUCCESS) {
                // 文件传输成功
                break;
            }
        } while (1);
        
        fclose(f);
        file_count++;
    } while (1);
    
    // 5. 发送状态响应
    plist_t empty_plist = plist_new_dict();
    mobilebackup2_send_status_response(mobilebackup2, 0, NULL, empty_plist);
    plist_free(empty_plist);
    
    return file_count;
}
```

---

## Status.plist 机制

### 作用和重要性

Status.plist 是备份状态的持久化文件，用于：
1. 记录备份/恢复操作的最终状态
2. 区分完整备份和增量备份
3. 验证备份完整性
4. 提供错误诊断信息

### 文件位置

```
备份目录结构:
{backup_directory}/
  └── {device_udid}/
      ├── Status.plist      ← 状态文件
      ├── Info.plist        ← 设备信息
      ├── Manifest.plist    ← 文件清单
      └── {hash}/           ← 备份文件(按SHA1哈希组织)
```

### Status.plist 格式

#### MobileBackup2 (新版)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SnapshotState</key>
    <string>finished</string>  <!-- 或 "running", "failed" -->
    
    <key>Version</key>
    <string>2.1</string>
    
    <key>Date</key>
    <date>2024-01-01T00:00:00Z</date>
    
    <key>IsFullBackup</key>
    <true/>
    
    <key>BackupState</key>
    <string>Finished</string>
</dict>
</plist>
```

#### MobileBackup (旧版)

```xml
<dict>
    <key>Backup Success</key>
    <true/>  <!-- 或 <false/> -->
</dict>
```

### 状态检查实现

```c
// 检查备份状态 (tools/idevicebackup2.c:609-634)
static int mb2_status_check_snapshot_state(const char *path, 
                                           const char *udid, 
                                           const char *matches)
{
    int ret = 0;
    plist_t status_plist = NULL;
    
    // 1. 读取 Status.plist
    char *file_path = string_build_path(path, udid, "Status.plist", NULL);
    plist_read_from_file(file_path, &status_plist, NULL);
    free(file_path);
    
    if (!status_plist) {
        printf("Could not read Status.plist!\n");
        return ret;
    }
    
    // 2. 获取 SnapshotState 值
    plist_t node = plist_dict_get_item(status_plist, "SnapshotState");
    if (node && (plist_get_node_type(node) == PLIST_STRING)) {
        char* sval = NULL;
        plist_get_string_val(node, &sval);
        
        // 3. 比较状态
        if (sval) {
            ret = (strcmp(sval, matches) == 0) ? 1 : 0;
            free(sval);
        }
    } else {
        printf("ERROR: could not get SnapshotState key from Status.plist!\n");
    }
    
    plist_free(status_plist);
    return ret;
}
```

### Status.plist 的设置时机

#### 1. 备份开始前

设备可能请求读取现有的 Status.plist 以决定是否执行增量备份：

```c
// 设备请求 DLMessageDownloadFiles
// 文件列表包含: "00008110-000664261A83801E/Status.plist"

// 主机响应:
if (file_exists(Status.plist)) {
    // 发送现有文件 → 设备执行增量备份
    send_file(Status.plist);
} else {
    // 发送错误或空文件 → 设备执行完整备份
    send_error(ENOENT);
}
```

#### 2. 备份进行中

设备自动更新 Status.plist（通过 DLMessageUploadFiles）：

```xml
<dict>
    <key>SnapshotState</key>
    <string>running</string>
    <key>BackupState</key>
    <string>InProgress</string>
</dict>
```

#### 3. 备份完成后

设备发送最终状态：

```xml
<dict>
    <key>SnapshotState</key>
    <string>finished</string>
    <key>BackupState</key>
    <string>Finished</string>
</dict>
```

#### 4. 恢复前验证

```c
// 恢复前必须验证备份状态 (tools/idevicebackup2.c:2078-2082)
if (!mb2_status_check_snapshot_state(backup_directory, source_udid, "finished")) {
    printf("ERROR: Cannot ensure we restore from a successful backup.\n");
    return -1;
}
```

### 常见错误及解决

#### 错误 103: Error reading status

```
错误信息:
ErrorCode: 103
ErrorDescription: Error reading status (MBErrorDomain/103). 
                  Underlying error: Error creating from path at path 
                  "00008110-000664261A83801E/Status.plist" (MBErrorDomain/1).
```

**原因分析**:
1. Status.plist 文件格式错误（不是有效的 plist）
2. 文件传输协议不正确（长度帧格式错误）
3. 文件路径不正确

**解决方案**:

```c
// 方案1: 不创建 Status.plist，让设备处理缺失情况
if (file_is_Status_plist(path)) {
    // 发送 ENOENT 错误
    uint32_t nlen = htobe32(strlen(error_msg) + 1);
    buf[4] = CODE_ERROR_LOCAL;
    mobilebackup2_send_raw(...);
    
    // 不要发送终止标记，继续处理下一个文件
}

// 方案2: 如果必须创建，使用正确格式
plist_t status = plist_new_dict();
plist_dict_set_item(status, "SnapshotState", plist_new_string("finished"));
plist_dict_set_item(status, "Version", plist_new_string("2.1"));
plist_dict_set_item(status, "IsFullBackup", plist_new_bool(1));

// 保存为二进制格式
char *plist_bin = NULL;
uint32_t plist_bin_size = 0;
plist_to_bin(status, &plist_bin, &plist_bin_size);

// 按协议发送
send_file_with_proper_framing(plist_bin, plist_bin_size);
```

---

## 代码示例

### 完整的备份流程示例

```c
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/mobilebackup2.h>

int perform_backup(const char *udid, const char *backup_dir)
{
    idevice_t device = NULL;
    lockdownd_client_t lockdown = NULL;
    mobilebackup2_client_t mobilebackup2 = NULL;
    lockdownd_service_descriptor_t service = NULL;
    
    // 1. 连接设备
    if (idevice_new(&device, udid) != IDEVICE_E_SUCCESS) {
        return -1;
    }
    
    // 2. 启动 lockdown 服务
    if (lockdownd_client_new_with_handshake(device, &lockdown, "backup_tool") 
        != LOCKDOWN_E_SUCCESS) {
        idevice_free(device);
        return -1;
    }
    
    // 3. 启动 mobilebackup2 服务
    if (lockdownd_start_service(lockdown, "com.apple.mobilebackup2", &service) 
        != LOCKDOWN_E_SUCCESS) {
        lockdownd_client_free(lockdown);
        idevice_free(device);
        return -1;
    }
    
    // 4. 创建 mobilebackup2 客户端
    if (mobilebackup2_client_new(device, service, &mobilebackup2) 
        != MOBILEBACKUP2_E_SUCCESS) {
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(lockdown);
        idevice_free(device);
        return -1;
    }
    
    // 5. 构建备份选项
    plist_t options = plist_new_dict();
    plist_dict_set_item(options, "ForceFullBackup", plist_new_bool(1));
    
    // 6. 发送备份请求
    if (mobilebackup2_send_request(mobilebackup2, "Backup", udid, udid, options)
        != MOBILEBACKUP2_E_SUCCESS) {
        plist_free(options);
        goto cleanup;
    }
    plist_free(options);
    
    // 7. 消息处理循环
    plist_t message = NULL;
    char *dlmsg = NULL;
    int done = 0;
    
    while (!done) {
        mobilebackup2_receive_message(mobilebackup2, &message, &dlmsg);
        
        if (!strcmp(dlmsg, "DLMessageDownloadFiles")) {
            // 处理文件下载请求
            mb2_handle_send_files(mobilebackup2, message, backup_dir);
        }
        else if (!strcmp(dlmsg, "DLMessageUploadFiles")) {
            // 处理文件上传
            mb2_handle_receive_files(mobilebackup2, message, backup_dir);
        }
        else if (!strcmp(dlmsg, "DLMessageProcessMessage")) {
            // 处理状态消息
            plist_t node = plist_array_get_item(message, 1);
            plist_t error_code = plist_dict_get_item(node, "ErrorCode");
            if (error_code) {
                uint64_t ec = 0;
                plist_get_uint_val(error_code, &ec);
                if (ec != 0) {
                    printf("Backup failed with error: %llu\n", ec);
                    done = 1;
                }
            }
        }
        else if (!strcmp(dlmsg, "DLMessageDisconnect")) {
            done = 1;
        }
        
        plist_free(message);
        free(dlmsg);
    }
    
    // 8. 验证备份状态
    int success = mb2_status_check_snapshot_state(backup_dir, udid, "finished");
    
cleanup:
    mobilebackup2_client_free(mobilebackup2);
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(lockdown);
    idevice_free(device);
    
    return success ? 0 : -1;
}
```

---

## 常见问题

### Q1: 如何触发完整备份而不是增量备份？

**方法1**: 设置 ForceFullBackup 选项
```c
plist_dict_set_item(options, "ForceFullBackup", plist_new_bool(1));
```

**方法2**: 不提供或删除现有的 Status.plist
```c
// 当设备请求 Status.plist 时，返回 ENOENT 错误
if (strcmp(filename, "Status.plist") == 0) {
    send_error(CODE_ERROR_LOCAL, "File not found");
}
```

### Q2: 如何正确处理文件传输中的错误？

```c
// 发送文件时的错误处理
int send_file_with_error_handling(const char *path, plist_t *errplist)
{
    if (!file_exists(path)) {
        // 添加到错误列表
        if (!*errplist) {
            *errplist = plist_new_dict();
        }
        mb2_multi_status_add_file_error(*errplist, path, 
                                        errno_to_device_error(ENOENT),
                                        strerror(ENOENT));
        
        // 发送错误帧
        send_error_frame(CODE_ERROR_LOCAL, strerror(ENOENT));
        return -1;
    }
    
    // 正常发送文件...
    return 0;
}
```

### Q3: 如何实现进度报告？

```c
// 提取进度信息
static void mb2_set_overall_progress_from_message(plist_t message, char* identifier)
{
    plist_t node = NULL;
    double progress = 0.0;
    
    if (!strcmp(identifier, "DLMessageDownloadFiles")) {
        node = plist_array_get_item(message, 3);  // 第4个元素是进度
    } else if (!strcmp(identifier, "DLMessageUploadFiles")) {
        node = plist_array_get_item(message, 2);  // 第3个元素是进度
    }
    
    if (node != NULL) {
        plist_get_real_val(node, &progress);
        printf("Progress: %.1f%%\n", progress);
    }
}
```

### Q4: 如何处理备份加密？

```c
plist_t options = plist_new_dict();
plist_dict_set_item(options, "Password", plist_new_string("your_password"));
plist_dict_set_item(options, "WillEncrypt", plist_new_bool(1));
```

### Q5: 如何实现选择性恢复？

```c
// 恢复特定应用数据
plist_t options = plist_new_dict();
plist_t apps = plist_new_dict();

// 添加要恢复的应用
plist_dict_set_item(apps, "com.example.app", plist_new_bool(1));
plist_dict_set_item(options, "RestoreApplications", apps);

// 不恢复系统文件
plist_dict_set_item(options, "RestoreShouldReboot", plist_new_bool(0));
plist_dict_set_item(options, "RestoreSystemFiles", plist_new_bool(0));

mobilebackup2_send_request(client, "Restore", target_id, source_id, options);
```

---

## 参考资料

### 相关文件
- `src/mobilebackup2.c` - MobileBackup2 客户端实现
- `src/mobilebackup2.h` - MobileBackup2 头文件
- `tools/idevicebackup2.c` - 命令行工具实现
- `src/device_link_service.c` - DeviceLink 服务实现

### 关键函数
- [`mobilebackup2_client_new()`](src/mobilebackup2.c:71) - 创