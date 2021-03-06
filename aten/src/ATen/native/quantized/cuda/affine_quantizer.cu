#include <ATen/native/TensorIterator.h>
#include <ATen/native/quantized/affine_quantizer.h>
#include <math.h>
#include <ATen/cuda/CUDAApplyUtils.cuh>
#include <ATen/native/cuda/Loops.cuh>

namespace at {
namespace native {
namespace {

void quantize_tensor_per_tensor_affine_cuda(
    Tensor rtensor,
    Tensor qtensor,
    double scale,
    int64_t zero_point) {
  AT_DISPATCH_QINT_TYPES(
      qtensor.scalar_type(), "quantize_tensor_per_tensor_affine_cuda", [&]() {
        constexpr int64_t qmin = std::numeric_limits<underlying_t>::min();
        constexpr int64_t qmax = std::numeric_limits<underlying_t>::max();
        at::cuda::CUDA_tensor_apply2<float, scalar_t>(
            /*a=*/rtensor,
            /*b=*/qtensor,
            [=] __device__(float& rtensor_val, scalar_t& qtensor_val) {
              int64_t qvalue;
              qvalue = static_cast<int64_t>(
                  nearbyint(rtensor_val / scale + zero_point));
              qvalue = std::max<int64_t>(qvalue, qmin);
              qvalue = std::min<int64_t>(qvalue, qmax);
              qtensor_val.val_ = qvalue;
            },
            /*aType=*/at::cuda::TensorArgType::ReadOnly,
            /*bType=*/at::cuda::TensorArgType::ReadWrite);
      });
}

void dequantize_tensor_per_tensor_affine_cuda(
    Tensor qtensor,
    Tensor rtensor,
    double scale,
    int64_t zero_point) {
  AT_DISPATCH_QINT_TYPES(
      qtensor.scalar_type(), "dequantize_tensor_per_tensor_affine_cuda", [&]() {
        auto iter = TensorIterator();
        iter.add_output(rtensor);
        iter.add_input(qtensor);
        iter.dont_compute_common_dtype();
        iter.build();
        gpu_kernel(iter, [=] GPU_LAMBDA(scalar_t value) -> float {
          return (static_cast<float>(value.val_) - zero_point) * scale;
        });
      });
}

} // anonymous namespace

REGISTER_DISPATCH(
    quantize_tensor_per_tensor_affine_stub,
    &quantize_tensor_per_tensor_affine_cuda);
REGISTER_DISPATCH(
    dequantize_tensor_per_tensor_affine_stub,
    &dequantize_tensor_per_tensor_affine_cuda);

} // namespace native
} // namespace at
