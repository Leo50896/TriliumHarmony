# 图片磁盘缓存

## 1. 目标

正文图片和全屏预览优先读本地文件，命中时完全跳过网络请求；未命中时才走
ETAPI 下载，并在成功后异步写盘。

## 2. 目录与文件名

```text
<cacheDir>/images/<md5>.img
```

- `cacheDir` 来自 `UIAbilityContext.cacheDir`；
- 文件名为 `MD5(serverUrl + "|" + src)`；
- `serverUrl` 参与 hash，避免不同服务器同路径图片串缓存；
- 使用 `.img` 扩展名，不依赖原图扩展名。

MD5 通过：

```ts
cryptoFramework.createMd('MD5')
```

计算。部分设备没有该系统能力时，降级为确定性 64-bit FNV 包装 hash，
保证同一 src 仍能得到稳定文件名。

## 3. 读取

`TriliumImage` / `ImagePreview` 在请求网络前：

```text
key = MD5(serverUrl|src)
path = cacheDir/images/<key>.img
if file exists:
  image.createImageSource(path)
  -> getImageInfo()
  -> createPixelMap()
  -> 直接渲染，不发网络请求
```

读取成功后调用 `fs.utimes(path, Date.now())` 刷新 mtime，作为 LRU 提示。

损坏文件会删除并回退网络。

## 4. 写入

网络下载返回 `ArrayBuffer` 后：

```ts
fs.openSync(path, CREATE | READ_WRITE | TRUNC)
fs.writeSync(fd, buffer)
fs.closeSync(file)
```

写入是 fire-and-forget，不阻塞 PixelMap 渲染；失败只忽略。

## 5. LRU 淘汰

每次写入后扫描 `images/`：

- 最多保留 **80** 个文件；
- 总大小最多 **50MB**；
- 按 `mtime` 从旧到新删除；
- 只处理 `.img` 文件。

## 6. 手动清理

设置页“数据与安全”新增：

```text
清理图片缓存    LRU 80 张
```

点击后调用 `ImageDiskCache.clear(context)`，删除 `cacheDir/images` 下的文件，
并提示“图片缓存已清理”。

设置页清理只删除图片缓存，不删除节点正文的 RDB 缓存。

## 7. 验证

- 图片请求成功后，沙箱出现：

```text
/data/app/el2/100/base/com.leo50896.triliumnotes/haps/entry/cache/images/
  0e0d85590ad75fc737c2ab5babf26dc8.img
```

- 文件大小 `123602` 字节；
- 临时强制图片网络请求失败，图片仍从上述缓存文件渲染成功；
- 进入设置点击“清理图片缓存”后，目录文件被删除；
- 临时测试笔记已通过 ETAPI 删除。

## 8. 边界

- 缓存是明文文件，不做加密；生产环境如需保护可结合 HUKS 或加密目录；
- 缓存按 `serverUrl|src` 区分，不按用户单独隔离；
- LRU 只在写入时触发，长期只读不会主动淘汰；
- 图片缓存独立于离线正文缓存；清理图片缓存不会影响 `note_cache`。
