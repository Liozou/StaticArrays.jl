using StaticArrays, Compat.Test

"""
Create an almost singular `Matrix{Float64}` of size `N×N`.

The first `rank` columns are chosen randomly, followed by `N-rank` linear
combinations with random weights to create an `N×N` singular matrix `S`.
A noise matrix of norm `ϵ*norm(S)` is added.

The condition number of this matrix should be approximately ϵ/eps(Float64)
"""
function almost_singular_matrix(N, rank, ϵ)
    B = rand(N,rank)
    weights = rand(rank, N-rank) ./ rank
    S = [B B*weights]
    S = S ./ norm(S)
    noise = rand(N,N)
    S + ϵ*norm(S)/norm(noise) * noise
end

@testset "Matrix inverse" begin
    @test inv(@SMatrix [2])::SMatrix ≈ @SMatrix [0.5]
    @test inv(@SMatrix [1 2; 2 1])::SMatrix ≈ [-1/3 2/3; 2/3 -1/3]
    @test inv(@SMatrix [1 2 0; 2 1 0; 0 0 1])::SMatrix ≈ [-1/3 2/3 0; 2/3 -1/3 0; 0 0 1]
    @test inv(@SMatrix [1+im 2 0; 1 2-im 1; 1 1 2+im])::SMatrix ≈ [2-2im  -3+1im   1-1im
                                                         -1+0im   2+1im  -1+0im
                                                          0+1im   0-1im   1-0.0im]/2

    m = randn(Float64, 10,10) + 10*I # well conditioned
    @test inv(SMatrix{10,10}(m))::StaticMatrix ≈ inv(m)


    # Unsigned versions
    @test inv(@SMatrix [0x01 0x02; 0x02 0x01])::SMatrix ≈ [-1/3 2/3; 2/3 -1/3]
    @test inv(@SMatrix [0x01 0x02 0x00; 0x02 0x01 0x00; 0x00 0x00 0x01])::SMatrix ≈ [-1/3 2/3 0; 2/3 -1/3 0; 0 0 1]

    m = triu(randn(Float64, 4,4) + 4*I)
    @test inv(SMatrix{4,4}(m))::StaticMatrix ≈ inv(m)
    m = tril(randn(Float64, 4,4) + 4*I)
    @test inv(SMatrix{4,4}(m))::StaticMatrix ≈ inv(m)
end


@testset "Matrix inverse 4x4" begin
    # A random well-conditioned matrix generated with `rand(1:10,4,4)`
    m = Float64[8 4 3 1;
                9 1 9 8;
                5 0 2 1;
                7 5 7 2]
    sm = SMatrix{4,4}(m)
    @test isapprox(inv(sm)::StaticMatrix, inv(m), rtol=2e-15)

    # A permutation matrix which can cause problems for inversion methods
    # without pivoting, eg 2x2 block decomposition (see #250)
    mperm = [1 0 0 0;
             0 0 1 0;
             0 1 0 0;
             0 0 0 1]
    @test inv(SMatrix{4,4}(mperm))::StaticMatrix ≈ inv(mperm)  rtol=2e-16

    # Poorly conditioned matrix; almost_singular_matrix(4, 3, 1e-7)
    m = [
        2.83056817904263402e-01 1.26822318692296848e-01 2.59665505365002547e-01 1.24524798964590747e-01
        4.29869029098094768e-01 2.29977256378012789e-03 4.63841570354149135e-01 1.51975221831027241e-01
        2.33883312850939995e-01 7.69469213907006122e-02 3.16525493661056589e-01 1.06181613512460249e-01
        1.63327582123091175e-01 1.70552365412100865e-01 4.55720450934200327e-01 1.23299968650232419e-01
    ]
    sm = SMatrix{4,4}(m)
    @test norm(Matrix(sm*inv(sm) - 4*I)) < 12*norm(m*inv(m) - 4*I)
    @test norm(Matrix(inv(sm)*sm - 4*I)) < 12*norm(inv(m)*m - 4*I)

    # Poorly conditioned matrix, generated by fuzz testing with
    # almost_singular_matrix(N, 3, 1e-7)
    # Case where the 4x4 algorithm fares badly compared to Base inv
    m = [1.80589503332920231e-02 2.37595944073211218e-01 3.80770755039433806e-01 5.70474286930408372e-02
         2.17494123374967520e-02 2.94069278741667661e-01 2.57334651147732463e-01 4.02348559939922357e-02
         3.42945636322714076e-01 3.29329508494837497e-01 2.25635541033857107e-01 6.03912636987153917e-02
         4.77828437366344727e-01 4.86406974015710591e-01 1.95415684569693188e-01 6.74775080892497797e-02]
    sm = SMatrix{4,4}(m)
    @test norm(Matrix(inv(sm)*sm - 4*I)) < 12*norm(inv(m)*m - 4*I)
    @test norm(Matrix(sm*inv(sm) - 4*I)) < 12*norm(m*inv(m) - 4*I)
end

@testset "Matrix inverse 5x5" begin
    m = randn(Float64, 5,5) + 5*I
    @test inv(SMatrix{5,5}(m))::StaticMatrix ≈ inv(m)
    m = triu(randn(Float64, 5,5) + 5*I)
    @test inv(SMatrix{5,5}(m))::StaticMatrix ≈ inv(m)
    m = tril(randn(Float64, 5,5) + 5*I)
    @test inv(SMatrix{5,5}(m))::StaticMatrix ≈ inv(m)
end

@testset "Matrix inverse ($typ, $sz×$sz)" for sz in (5, 8, 15), typ in (Float64, Complex{Float64})
    A = rand(typ, sz, sz)
    SA = SMatrix{sz,sz,typ}(A)
    @test inv(A) ≈ inv(SA)
end

#-------------------------------------------------------------------------------
# More comprehensive but qualitiative testing for inv() accuracy
#=
using PyPlot

inv_residual(A::AbstractMatrix) = norm(A*inv(A) - eye(size(A,1)))

"""
    plot_residuals(N, rank, ϵ)

Plot `inv_residual(::StaticMatrix)` vs `inv_residual(::Matrix)`

"""
function plot_residuals(N, rank, ϵ)
    A_residuals = []
    SA_residuals = []
    for i=1:10000
        A = almost_singular_matrix(N, rank, ϵ)
        SA = SMatrix{N,N}(A)
        SA_residual = norm(Matrix(SA*inv(SA) - eye(N)))
        A_residual = norm(A*inv(A) - eye(N))
        push!(SA_residuals, SA_residual)
        push!(A_residuals, A_residual)
        #= if SA_residual/A_residual > 10000 =#
        #=     @printf("%10e %.4f\n", SA_residual, SA_residual/A_residual) =#
        #=     println("[") =#
        #=     for i=1:4 =#
        #=         for j=1:4 =#
        #=             @printf("%.17e ", A[i,j]) =#
        #=         end =#
        #=         println() =#
        #=     end =#
        #=     println("]") =#
        #= end =#
    end
    loglog(A_residuals, SA_residuals, ".", markersize=1.5)
end

# Plot the accuracy of inv implementations for almost singular matrices of
# various rank
clf()
N = 4
title("inv() accuracy for poorly conditioned $(N)x$(N) - Base vs block decomposition")
labels = []
for i in N:-1:1
    plot_residuals(N, i, 1e-7)
    push!(labels, "rank $i")
end
xlabel("Residual norm: `inv(::Array)`")
ylabel("Residual norm: `inv(::StaticArray)`")
legend(labels)
=#
