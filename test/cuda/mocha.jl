function test_mocha_kernels(sys::System)
  println("-- Testing Mocha CUDA kernels")

  println("    > logistic loss forward")
  for data_type in [Float32, Float64]
    eps = 1e-5

    h, w, c, n = (5, 6, 7, 128)
    prob = abs(rand(data_type, (w,h,c,n))) + 0.1
    label = abs(rand(Int, (w, h, 1, n))) % c
    label = convert(Array{data_type}, label)

    prob_blob = make_blob(sys.backend, data_type, size(prob))
    copy!(prob_blob, prob)
    label_blob = make_blob(sys.backend, data_type, size(label))
    copy!(label_blob, label)

    # This should always be float32
    loss_blob = make_blob(sys.backend, Float32, 1)
    copy!(loss_blob, Float32[0])

    spatial_dim = h*w
    prob_dim = c

    x_block = int(ceil(float64(n)/CUDA.THREADS_PER_BLOCK))
    y_block = spatial_dim

    if data_type == Float32
      kernel = sys.backend.mocha.logistic_loss_forward_float
    else
      kernel = sys.backend.mocha.logistic_loss_forward_double
    end
    CUDA.launch(kernel, (x_block, y_block), (CUDA.THREADS_PER_BLOCK, 1),
        (prob_blob.ptr.p, label_blob.ptr.p, n, spatial_dim, prob_dim, loss_blob.ptr.p))

    loss = Float32[0]
    copy!(loss, loss_blob)
    loss = loss[1] / (n*h*w)

    # simulate CUDA blocking, because float is very inaccurate
    # adding 512 float32 of -log(0.1) will produce noticeable different
    # results (1e-2) from adding 256 of them and then add the two sums
    expected_loss = 0f0
    for j = 1:w
      for k = 1:h
        local_loss = 0f0
        for i = 1:n
          local_loss += -log(prob[j, k, int(label[j,k,1,i])+1, i])
        end
        expected_loss += local_loss
      end
    end
    expected_loss /= (n*h*w)

    #println("loss = $loss")
    #println("expected_loss = $expected_loss")
    @test (-eps < expected_loss - loss < eps)
  end
end

test_mocha_kernels(sys_cudnn)
