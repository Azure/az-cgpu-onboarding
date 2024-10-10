# OpenSSL
H100 CGPU system comes with OpenSSL version 3.0.2 installed by default. The sections below demonstrate the bandwidth improvement that come with upgrading the system to OpenSSL version 3.3.1.

Check your system's default OpenSSL version by running the following:
```
$ openssl version
```
You should see: `OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)`.

To use the newly installed OpenSSL 3.3.1, specify the `LD_LIBRARY_PATH` path:
```
$ LD_LIBRARY_PATH=/opt/openssl/lib64/ /opt/openssl/bin/openssl version
```
Here you should see: `OpenSSL 3.3.1 4 Jun 2024 (Library: OpenSSL 3.3.1 4 Jun 2024)`.

### CUDA application
Using the [bandwidth test](https://github.com/NVIDIA/cuda-samples/tree/master/Samples/1_Utilities/bandwidthTest) from NVIDIA's CUDA samples, we see the following improvements with upgrading from OpenSSL 3.0.2 to OpenSSL 3.3.1:


With system default OpenSSL 3.0.2:
```
$ ./bandwidthTest
[CUDA Bandwidth Test] - Starting...
Running on...

 Device 0: NVIDIA H100 NVL
 Quick Mode

 Host to Device Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     4.4

 Device to Host Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     4.4

 Device to Device Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     2191.5

Result = PASS
```

With OpenSSL 3.3.1:
```
$ LD_LIBRARY_PATH=/opt/openssl/lib64/ ./bandwidthTest
[CUDA Bandwidth Test] - Starting...
Running on...

 Device 0: NVIDIA H100 NVL
 Quick Mode

 Host to Device Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     8.6

 Device to Host Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     9.9

 Device to Device Bandwidth, 1 Device(s)
 PINNED Memory Transfers
   Transfer Size (Bytes)        Bandwidth(GB/s)
   32000000                     2127.9

Result = PASS
```

### PyTorch Script
Use the following PyTorch script to measure CPU-GPU bandwidth:
```python
import torch
import time

# Allocate host memory
num_elements = (16 * 1024 * 1024 * 1024) // 4
host_data = torch.randn(num_elements, dtype=torch.float32)
host_data_size = host_data.element_size() * host_data.nelement()

# Allocate device memory
device_data = torch.empty_like(host_data, device='cuda')

# Measure Host to Device bandwidth
start = time.perf_counter()
device_data.copy_(host_data)
end = time.perf_counter()
h2d_bandwidth = host_data_size / (end - start) / 1e9

print(f'Host to Device Bandwidth: {h2d_bandwidth:.2f} GB/s')

# Measure Device to Host bandwidth
start = time.perf_counter()
host_data.copy_(device_data)
end = time.perf_counter()
d2h_bandwidth = host_data_size / (end - start) / 1e9

print(f'Device to Host Bandwidth: {d2h_bandwidth:.2f} GB/s')
```

With system default OpenSSL 3.0.2:
```
$ python3 benchmark_pytorch.py
Host to Device Bandwidth: 4.27 GB/s
Device to Host Bandwidth: 4.45 GB/s
```

With OpenSSL 3.3.1:
```
$ LD_LIBRARY_PATH=/opt/openssl/lib64/ python3 benchmark_pytorch.py
Host to Device Bandwidth: 8.57 GB/s
Device to Host Bandwidth: 10.01 GB/s
```

### Docker

There are seval options to install OpenSSL 3.3.1 inside docker containers:
1. Run `utilities-install-openssl.sh` to build and install OpenSSL 3.3.1 inside the container.
2. Mount the OpenSSL 3.3.1 from the host if it's already installed by adding the argument `-v /opt/openssl:/opt/openssl` to `docker run`.

The usage of OpenSSL 3.3.1 inside the container is the same as above by specifying the linked OpenSSL 3.3.1 library path.

```
$ sudo docker run \
    --gpus all \
    --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
    -v ~:/home \
    -v /opt/openssl:/opt/openssl \
    -it --rm \
    nvcr.io/nvidia/pytorch:24.05-py3 \
    /bin/bash -c "LD_LIBRARY_PATH=/opt/openssl/lib64/ python3 /home/benchmark_pytorch.py"

Host to Device Bandwidth: 8.29 GB/s
Device to Host Bandwidth: 10.02 GB/s
```

Another approach is to set OpenSSL 3.3.1 as the default link inside the container to avoid explictly setting `LD_LIBRARY_PATH` every time.

```
echo '/opt/openssl/lib64' >> /etc/ld.so.conf.d/openssl.conf
ldconfig 
```

```
$ sudo docker run \
    --gpus all \
    --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
    -v ~:/home \
    -v /opt/openssl:/opt/openssl \
    -it --rm \
    nvcr.io/nvidia/pytorch:24.05-py3 \
    /bin/bash -c "echo '/opt/openssl/lib64' >> /etc/ld.so.conf.d/openssl.conf && ldconfig && python3 /home/benchmark_pytorch.py"

Host to Device Bandwidth: 8.43 GB/s
Device to Host Bandwidth: 10.06 GB/s
```
