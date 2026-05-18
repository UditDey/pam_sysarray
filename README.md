# Systolic Array using PAM Multiplication

Matrix multiplication systolic array using [Piecewise Approximate Multiplication](https://www.mdpi.com/2079-9292/11/12/1913) written in Verilog

PAM is an approximate floating point multiplication trick. It relies on the fact that the IEEE 754 FP representation when interpreted as an integer approximately encodes `log2(|x|)`. This allows us to do approximate multiplication only using integer addition/subtraction.

This project uses that trick to create a MAC (multiply-and-accumulate) unit that has significantly lower complexity than a true MAC unit. That MAC is then organized into a 2D systolic array for matrix multiplication (TPU style).

PAM can allow us to perform AI inference using far lower circuit complexity and energy usage, without sacrificing too much accuracy.


## PAM Explained
IEEE 754 encodes real numbers in terms of mantissa and exponent like so:

$$
A = (1 + M_A) \times 2^{E_A - bias}
$$
$$
B = (1 + M_B) \times 2^{E_B - bias}
$$

True multiplication is written as:

$$
A \times B = (1 + M_A) \cdot (1 + M_B) \times 2^{E_A + E_B - bias}
$$

$$
= (1 + M_A + M_B + M_A \cdot M_B) \times 2^{E_A + E_B - bias}
$$

For PAM approximate multiplication, add the 2 as integers and subtract bias:

$$
A \times B \approx I_A + I_B - bias = (1 + M_A + M_B) \times 2^{E_A + E_B - bias} 
$$

We can see that the two terms are almost identical, and only the $M_A \cdot M_B$ term is missing. That's our approximation error.
