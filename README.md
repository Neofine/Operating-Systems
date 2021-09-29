Projects I have done during Operational Systems course:
- first two are written in NASM
- next four are projects in which I modify MINIX core.

## Task 1
Programme in NASM that reads UTF-8 words from stdin and applies polynomial to each character, polynomial coefficients are read from programme arguments:

```
./diakrytynizator a0 a1 a2 ... an
```

And the formula applied to each character x is:

```
W(x) = (a_n * x^n + ... + a_2 * x^2 + a_1 * x + a_0) mod 0x10FF80
```

x is replaced by W(x – 0x80) + 0x80 and changed characters are written to output.


## Task 2

Programme in NASM that allows running concurrent instances of function 

```
uint64_t notec(uint32_t n, char const *calc)
```

Allows:
- Performing arithmetic operations
- Exchanging (concurrently) elements from top of the stack with other instances (uses spin lock)
- Call ```int64_t debug(uint32_t n, uint64_t *stack_pointer)``` function while satisfying ABI


## Task 3

Adds int ```negateexit(int negate)``` function to MINIX process manager.
Calling it with non-zero argument will negate process exit code, when argument is zero it restores original exit code.
This functionality is inherited by newly forked children.

## Task 4

Adds int ```setbid(int bit)``` function to MINIX.
Calling setbid with positive bid, changes process scheduling system, 
now it has always priority equal to 8, and when normal scheduling would go to priority = 8 then among 
those processes which have chosen this scheduling system it choses one with the lowest unique bid 
(if none are unique then process with highest bid is chosen), this method can lead to process starvation.
Calling setbid with bid = 0 restores default scheduling system.

## Task 5

Modified version of Minix File System which generates different kinds of errors:
-	Adds 1 to every third byte written to a file by MFS
-	Let every third chmod call negates S_IWOTH file permissions
-	When file is being removed and there is directory named ```debug``` in the same directory as the file
  instead of deleting it move it to this directory instead

## Task 6

MINIX device driver that implements simple queue with some additional operations, saves data even after ‘service update’ or ‘service restart’ commands.
