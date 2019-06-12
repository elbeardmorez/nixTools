# math.sh

## description
bc wrapper adding miscellaneous functionality that is otherwise either painful to remember (e.g. base conversion), or painful to repeatedly implement (e.g. comparitors)

## usage
```
SYNTAX: math_ [BASE] EXPRESSION [SCALE]

with

  BASE:  base conversion, supporting:

    d2h  : decimal to hex
    d2b  : decimal to binary
    h2d  : hex to decimal
    h2b  : hex to binary
    b2d  : binary to decimal
    b2h  : binary to hex

  EXPRESSION  : valid bc expression, with additional supported
                functions and operators

    functions:
      $abs  : absolute
      $gt  : greater than
      $ge  : greater than or equal to
      $lt  : less than
      $le  : less than or equal to
      $max  : maximum of two values
      $min  : minimum of two values
      $factorial  : factorials
      $npr  : permutations
      $ncr  : combinations

    operators:
      !  : factorials
      nPr  : permutions
      nCr  : combinations

  SCALE  : bc's notion of significant digits after the period
```

## examples
```sh
$ math_ 6!
720
```
```sh
$ math_ 10P2
90
```
```sh
$ math_ 16C13
560
```
```sh
$ math_ d2h 30
1E
```
```sh
$ math_ b2d 1111
15
```
```sh
$ math_ h2b ef
11101111
```
```sh
$ math_ '$max(67*12, 60*13)'
804
```
```sh
$ math_ '$abs(-10 * $min(9*11, 10^2))'
990
```

# dependencies
- bc
