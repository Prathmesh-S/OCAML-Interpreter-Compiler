####################################################
import sys
sys.path.append("./../../../../classlib/Python")
from MyPython import *

#Problem 5

def fnlist_make_fwork(func):
    newList = fnlist_nil()

    def work(node):
        nonlocal newList 
        newList =  fnlist_cons(1, x0, newList)
    work(funct)
    newList= fnlist_reverse(newList)
    return(newList)