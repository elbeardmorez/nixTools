# dates

## description
date related functionality

## usage
### `edit`
cycle date parts, modify and hit `x`
> Thu 23 Aug 2018, 15:**57**:21 BST (+0100) [modify (⇧|⇩) / select part (⇦|⇨) / \(c\)ancel / e\(x\)it] ⇧

>⇧ | ⇩  : modify (increment/decrement) current part of date  
>⇦ | ⇨  : select current part of date  
>c | C  : cancel / abort editing  
>x | X  : exit / done editing  

- inline editing
```
  > dt_mod=$(_dates "`date -d "now + 1 month"  +"%c"`")
  > echo "$dt_mod | `date -d @$dt_mod`"`nth"  +"%c"`")
  1535036241 | Thu 23 Aug 15:57:21 BST 2018
```
- edit the current date
```
  > _dates
```

## dependencies
### `edit`
- GNU coreutils  : `date`, specifically parsing from epoch `-d@` and arbitrary addition

