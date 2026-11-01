function automatic [M-1:0] gf_mul(
    input [M-1:0] a_i,
    input [M-1:0] b_i
);
    reg [M:0] a;
    reg [M-1:0] b;
    reg [M-1:0] result;
    integer bit_index;
    begin
        a = {1'b0, a_i};
        b = b_i;
        result = '0;
        for (bit_index = 0; bit_index < M; bit_index = bit_index + 1) begin
            if (b[0])
                result = result ^ a[M-1:0];
            b = b >> 1;
            a = a << 1;
            if (a[M])
                a = a ^ PRIMITIVE_POLYNOMIAL;
        end
        gf_mul = result;
    end
endfunction

function automatic [M-1:0] gf_square(input [M-1:0] a_i);
    begin
        gf_square = gf_mul(a_i, a_i);
    end
endfunction

