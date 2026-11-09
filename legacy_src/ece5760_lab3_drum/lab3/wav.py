from os.path import dirname, join
import scipy.io.wavfile as wf
import numpy as np
RATE = 44100

current_dir = dirname(__file__)
file_path1 = join(current_dir, "log.txt")
file_path2 = join(current_dir, "float.txt")
wav_file_dir = join(current_dir, 'test.wav')

file1=open(file_path1,"r")
file2=open(file_path2,"w")
def fix2float28(a):
    f = ((float)(a)/268435456.0) 
    #print(f)
    return f
def to_float(x,e):
    c = abs(x)
    sign = 1 
    if getbit(x,17) == 1:
        print(x)
        sign = -1
    f = (1.0 * c) / (2 ** e)
    f = f * sign
    return f
def getbit(x,n):
  "Get the n-th bit of the number x"
  return x & (1 << n) and 1 or 0
data = []
# Iterate over each line in the file
with open(file_path1, "r") as file1:
    for line in file1:
        line = line.strip()
        result = to_float(int(line,16),16)
        #result = fix2float28(int(line,16))
        data.append(result)
        file2.write(str(result)+"\n")
# Release used resources
file1.close()
file2.close()
data_n = np.array(data, dtype=np.float32)
wf.write(wav_file_dir, RATE, data_n)
