# ORX-1 Data Bus Contract

The CPU master uses a single outstanding request interface. A request is presented with `req_valid`, address, direction, write data, and byte strobes. The target accepts it when `req_ready` is high. A response is returned with `rsp_valid`; reads use `rsp_rdata`, while any invalid or unmapped access is reported with `rsp_err`.

| Signal | Direction | Meaning |
|---|---|---|
| `req_valid` | master to fabric | Request is present and must remain stable until accepted. |
| `req_ready` | fabric to master | Fabric accepts the request on the rising edge. |
| `req_write` | master to fabric | `1` for a write, `0` for a read. |
| `req_addr` | master to fabric | Byte address. |
| `req_wdata` | master to fabric | Write payload. |
| `req_wstrb` | master to fabric | Active byte lanes, low bit is the least-significant byte. |
| `rsp_valid` | fabric to master | Response is present. |
| `rsp_rdata` | fabric to master | Read response data. |
| `rsp_err` | fabric to master | Access was unmapped or otherwise invalid. |

The current reference fabric responds in the same cycle as acceptance. The CPU nevertheless has a `MEM_WAIT` state so a derivative fabric can insert one or more response cycles without changing the CPU-facing contract.

A future revision should add `rsp_ready` if multiple outstanding transactions or independent response backpressure are required. The current single-outstanding design intentionally keeps ordering and verification simple.
