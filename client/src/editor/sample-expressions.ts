/**
 * Provide the notebook’s initial cursor-navigation examples. Contains 20 labeled LaTeX expressions spanning algebra, logic, matrices, calculus, probability, and optimization.
 *
 * @file
 */

export const sampleExpressions = [
  {
    title: 'Fraction terms',
    latex: String.raw`\frac{1}{2}+\frac{1}{3}+\frac{1}{4}+\frac{1}{5}`,
  },
  {
    title: 'Uneven nesting',
    latex: String.raw`\frac{a+\frac{b}{c}}{d}+e`,
  },
  {
    title: 'Fractions within fractions',
    latex: String.raw`\frac{\frac{a+b}{c}}{\frac{d}{e+f}}`,
  },
  {
    title: 'Powers and subscripts',
    latex: String.raw`x_i^{n+1}+a_{j_k}^{m^2}+\left(x+y\right)^3`,
  },
  {
    title: 'Nested roots',
    latex: String.raw`\sqrt{1+\sqrt{1+x^2}}+\sqrt[3]{\frac{a+b}{c}}`,
  },
  {
    title: 'Algebra and grouped factors',
    latex: String.raw`\frac{\left(x+1\right)\left(x-2\right)}{x^2+3x+2}=\frac{x-2}{x+2}`,
  },
  {
    title: 'Logic and quantifiers',
    latex: String.raw`\forall x\in X\;\left(P(x)\Rightarrow\exists y\in Y\;\left(Q(x,y)\land\neg R(y)\right)\right)`,
  },
  {
    title: 'Logical equivalence',
    latex: String.raw`\neg\left(P\land\left(Q\lor R\right)\right)\Leftrightarrow\left(\neg P\lor\left(\neg Q\land\neg R\right)\right)`,
  },
  {
    title: 'Sets and indexed unions',
    latex: String.raw`\bigcup_{i=1}^{n}\left(A_i\cap B\right)\subseteq\left(\bigcup_{i=1}^{n}A_i\right)\cap B`,
  },
  {
    title: 'Matrix with structured entries',
    latex: String.raw`A=\begin{pmatrix}\frac{1}{2}&x^2&0\\\sqrt{y}&a_{ij}&1\\0&\frac{b}{c+d}&\lambda\end{pmatrix}`,
  },
  {
    title: 'Matrix and vector multiplication',
    latex: String.raw`\begin{pmatrix}a&b\\c&d\end{pmatrix}\begin{pmatrix}x\\y\end{pmatrix}=\begin{pmatrix}ax+by\\cx+dy\end{pmatrix}`,
  },
  {
    title: 'Summation and product',
    latex: String.raw`\sum_{i=1}^{n}\frac{x_i^2}{1+x_i}=\prod_{j=1}^{m}\left(1+\frac{1}{j}\right)`,
  },
  {
    title: 'Nested sums',
    latex: String.raw`\sum_{i=1}^{n}\sum_{j=1}^{i}\frac{a_{ij}}{i+j}`,
  },
  {
    title: 'Definite integral',
    latex: String.raw`\int_{0}^{1}\frac{x^2+1}{\sqrt{1-x^2}}\,\mathrm{d}x`,
  },
  {
    title: 'Iterated integrals',
    latex: String.raw`\int_{0}^{1}\int_{0}^{x}\left(x^2+y^2\right)\,\mathrm{d}y\,\mathrm{d}x`,
  },
  {
    title: 'Derivatives and limits',
    latex: String.raw`\frac{\partial^2 f}{\partial x\,\partial y}=\lim_{h\to0}\frac{f_x(x,y+h)-f_x(x,y)}{h}`,
  },
  {
    title: 'Piecewise function',
    latex: String.raw`f(x)=\begin{cases}\frac{x^2-1}{x-1}&x\ne1\\2&x=1\end{cases}`,
  },
  {
    title: 'Probability and conditioning',
    latex: String.raw`P(A\mid B)=\frac{P(B\mid A)P(A)}{\sum_{i=1}^{n}P(B\mid A_i)P(A_i)}`,
  },
  {
    title: 'Optimization',
    latex: String.raw`x^*=\operatorname*{arg\,min}_{x\in\mathbb{R}^n}\left(\frac{1}{2}\lVert Ax-b\rVert_2^2+\lambda\lVert x\rVert_1\right)`,
  },
  {
    title: 'Complex numbers and Fourier series',
    latex: String.raw`f(t)=\sum_{k=-\infty}^{\infty}c_k e^{\mathrm{i}kt},\quad c_k=\frac{1}{2\pi}\int_{-\pi}^{\pi}f(t)e^{-\mathrm{i}kt}\,\mathrm{d}t`,
  },
]
