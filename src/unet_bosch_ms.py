import tensorflow as tf
from tensorflow.keras import Model
from tensorflow.keras.layers import Conv2D, MaxPooling2D, Input, concatenate, Dropout, UpSampling2D
from tensorflow.keras.optimizers import Adam
from tensorflow.python.framework.errors_impl import ResourceExhaustedError
import numpy as np
import time
import os

### USER CONFIG #################################
num_images = 128
batch_sizes = [1,2,4,8,16,32]
input_shape_x = 720
input_shape_y = 1280
input_shape_z = 1
np.random.seed(42)
first_layer_filters = 6 #scale the network
enable_callback = True
tensorflow_1_compat = False
os.environ["CUDA_VISIBLE_DEVICES"]="0"
################################################

class TimeHistory(tf.keras.callbacks.Callback):
    def on_train_begin(self, logs={}):
        self.times = []

    def on_epoch_begin(self, epoch, logs={}):
        self.time_start = time.time()

    def on_epoch_end(self, epoch, logs={}):
        self.times.append(time.time() - self.time_start)

def unet(input_size):
    inputs = Input(input_size)
    conv1 = Conv2D(first_layer_filters*1, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(inputs)
    pool1 = MaxPooling2D(pool_size=(2, 2))(conv1)
    conv2 = Conv2D(first_layer_filters*2, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool1)
    pool2 = MaxPooling2D(pool_size=(2, 2))(conv2)
    conv3 = Conv2D(first_layer_filters*4, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool2)
    pool3 = MaxPooling2D(pool_size=(2, 2))(conv3)
    conv4 = Conv2D(first_layer_filters*8, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool3)
    drop4 = Dropout(0.5)(conv4)
    pool4 = MaxPooling2D(pool_size=(2, 2))(drop4)

    conv5 = Conv2D(first_layer_filters*16, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool4)
    drop5 = Dropout(0.5)(conv5)
    pool5 = MaxPooling2D(pool_size=(3, 2))(drop5)

    conv51 = Conv2D(first_layer_filters*32, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool5)
    drop51 = Dropout(0.5)(conv51)
    pool51 = MaxPooling2D(pool_size=(3, 2))(drop51)

    conv52 = Conv2D(first_layer_filters*64, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(pool51)
    drop52 = Dropout(0.5)(conv52)

    up62 = Conv2D(first_layer_filters*32, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (3,2))(drop52))
    merge62 = concatenate([drop51,up62], axis = 3)
    conv62 = Conv2D(first_layer_filters*32, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge62)

    up61 = Conv2D(first_layer_filters*16, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (3,2))(conv62))
    merge61 = concatenate([drop5,up61], axis = 3)
    conv61 = Conv2D(first_layer_filters*16, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge61)

    up6 = Conv2D(first_layer_filters*8, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (2,2))(conv61))
    merge6 = concatenate([drop4,up6], axis = 3)
    conv6 = Conv2D(first_layer_filters*8, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge6)

    up7 = Conv2D(first_layer_filters*4, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (2,2))(conv6))
    merge7 = concatenate([conv3,up7], axis = 3)
    conv7 = Conv2D(first_layer_filters*4, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge7)

    up8 = Conv2D(first_layer_filters*2, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (2,2))(conv7))
    merge8 = concatenate([conv2,up8], axis = 3)
    conv8 = Conv2D(first_layer_filters*2, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge8)

    up9 = Conv2D(first_layer_filters*1, 2, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(UpSampling2D(size = (2,2))(conv8))
    merge9 = concatenate([conv1,up9], axis = 3)
    conv9 = Conv2D(first_layer_filters*1, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(merge9)
    conv10 = Conv2D(first_layer_filters*1, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(conv9)
    conv11 = Conv2D(2, 3, activation = 'relu', padding = 'same', kernel_initializer = 'he_normal')(conv10)
    conv12 = Conv2D(1, 1, activation = 'sigmoid')(conv11)

    model = Model(inputs = inputs, outputs = conv12)

    model.compile(optimizer = Adam(lr = 1e-4), loss = 'binary_crossentropy', metrics = ['accuracy'])
    

    return model

if tensorflow_1_compat:
    session_conf = tf.compat.v1.ConfigProto()
    sess = tf.compat.v1.Session(config=session_conf)

input_shape = (input_shape_x, input_shape_y, input_shape_z)

X = np.random.random(size=(num_images, input_shape[0], input_shape[1], input_shape[2])).astype('float32')
y = np.random.randint(2, size=(num_images, input_shape[0], input_shape[1], input_shape[2])).astype('uint8')

model = unet(input_shape)
model.summary()

time_callback = TimeHistory()
results = []

if enable_callback:
    callbacks = [time_callback]
else:
    callbacks = []
    
for batch_size in batch_sizes:
    try:
        model.fit(X, y, batch_size=batch_size, epochs=1, callbacks=callbacks)
        if enable_callback:
            print("Images: {} | Batch Size: {} | Time: {:.3g} | Time/image: {:.3g}".format(num_images, batch_size, time_callback.times[0], time_callback.times[0]/num_images))
            results.append([num_images, batch_size, time_callback.times[0], time_callback.times[0]/num_images])
    except ResourceExhaustedError as e:
        print("Error with batch size {} : {}".format(batch_size, e))

print("Images | Batch Size | Time | Time/image")
print("--- | --- | --- | --- ")
for result in results:
    print(' | '.join(map(str,result)))

