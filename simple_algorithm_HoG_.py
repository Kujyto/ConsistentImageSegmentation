#!/usr/bin/python 
# -*- coding: utf-8 -*-
# -*- coding: GBK -*-
# -*- coding: utf-8 -*-
# -*- coding: gb2312 -*-
import numpy as np
import scipy
from skimage.feature import hog
from skimage import data, color, exposure
import cv2
from skimage.draw._draw import line


def draw_hog(orientation_histogram, w_sz_x, w_sz_y, c_sz_x, c_sz_y, n_bins):
    orientations = n_bins
    n_cellsx = int(np.floor(w_sz_x // c_sz_x))  # number of cells in x
    n_cellsy = int(np.floor(w_sz_y // c_sz_y))  # number of cells in y
    radius = min(c_sz_x, c_sz_y) // 2 - 1  # - 1
    hog_image = np.zeros((w_sz_x, w_sz_y), dtype=float)
    #     for x in range(n_cellsx):
    #         for y in range(n_cellsy):
    for y in range(n_cellsy):
        for x in range(n_cellsx):
            for o in range(orientations):
                centre = tuple([y * c_sz_y + c_sz_y // 2, x * c_sz_x + c_sz_x // 2])
                #                 dx = radius * scipy.cos(float(o) / orientations * np.pi)
                #                 dy = radius * scipy.sin(float(o) / orientations * np.pi)
                dy = radius * scipy.cos(float(o) / orientations * np.pi)
                dx = radius * scipy.sin(float(o) / orientations * np.pi)
                rr, cc = line(int(centre[0] - dx),
                              int(centre[1] + dy),
                              int(centre[0] + dx),
                              int(centre[1] - dy))
                hog_image[rr, cc] += orientation_histogram[y, x, o]
    return hog_image


def HoG(img, std_length):
    n_bin = 9
    b_size = 8
    b_stride = 8  # 5
    c_size = 8

    ### skimage.feature method ########
    h, w, z = np.shape(img)
    img = cv2.resize(img, (std_length, std_length), interpolation=cv2.INTER_AREA)
    img = img[:, :, 1]

    fd, hog_image = hog(img, orientations=n_bin, pixels_per_cell=(c_size, c_size),
                        cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)

    # Rescale histogram for better display
    hog_image_rescaled = exposure.rescale_intensity(hog_image, in_range=(0, 0.02))  # 0.02
    hog_image_rescaled = cv2.resize(hog_image_rescaled, (w, h), interpolation=cv2.INTER_AREA)  # (weight, height)

    ### OpenCV method  (yet no direct image visualization method) ###
    # If all pictures are resized to a uniform scale, then we could not get the size feature

    hog_vc = cv2.HOGDescriptor((std_length, std_length), (b_size, b_size), \
                               (b_stride, b_stride), (c_size, c_size), n_bin)

    h_ori = hog_vc.compute(img)
    h_ori = np.ravel(h_ori)
    len_h_ori = len(h_ori)
    len_temp_1 = len_h_ori / n_bin

    h_temp_1 = np.zeros((len_temp_1, n_bin))
    for i in range(len_temp_1):
        for j in range(n_bin):
            h_temp_1[i, j] = h_ori[i * n_bin + j]
    print 'len_h_ori = ', len_h_ori  # 39204
    print 'len(h_temp_1) = ', len(h_temp_1)  # 4356

    len_temp_2 = std_length / c_size  # number of cells on each row/column

    block_temp_all = np.zeros((len_temp_2, len_temp_2, n_bin))
    block_all_count = np.zeros((len_temp_2, len_temp_2))

    n_c_per_b = b_size / c_size
    t_i = 0
    t_j = 0
    b_i = 0
    b_j = 0
    shift_x = 0
    shift_y = 0

    for q in range(len(h_temp_1)):

        b_t_cnt = np.ones((n_c_per_b, n_c_per_b))
        block_temp = np.zeros((n_c_per_b, n_c_per_b, n_bin))
        block_temp[t_i, t_j, :] = h_temp_1[q, :]
        t_j += 1
        if t_j >= n_c_per_b:
            t_j = 0
            t_i += 1
        if t_i >= n_c_per_b:
            t_i = 0

            # when the block is formed already, then we are to prepare the next block
            # to see if it is the right block to fill
            if shift_x % c_size == 0 and shift_y % c_size == 0:

                block_all_count[b_i: b_i + n_c_per_b, b_j: b_j + n_c_per_b] += b_t_cnt
                block_temp_all[b_i: b_i + n_c_per_b, b_j: b_j + n_c_per_b, :] += block_temp

                b_j += 1
                if b_j + n_c_per_b > len_temp_2:  # len_temp_2: number of cells per row
                    b_j = 0
                    b_i += 1

            # block has a shift_x of b_stride
            shift_x += b_stride

            if shift_x + b_size > std_length:
                shift_x = 0
                shift_y += b_stride

    max_value = np.max(block_temp_all)
    for i in range(len_temp_2):
        for j in range(len_temp_2):
            block_temp_all[i, j, :] = 255 * (block_temp_all[i, j, :] / (1.0 * block_all_count[i, j])) / (
                1.0 * max_value)

    orientation_histogram = block_temp_all
    print "HoG_shape_orientation_histogram", np.shape(orientation_histogram)
    print 'max(orientation_histogram) = ', np.max(orientation_histogram)

    hog_image_hist = draw_hog(orientation_histogram, \
                              w_sz_x=std_length, w_sz_y=std_length, \
                              c_sz_x=c_size, c_sz_y=c_size, n_bins=n_bin)

    hog_image_hist = np.transpose(hog_image_hist)
    return h_ori, hog_image_rescaled, hog_image_hist


if __name__ == '__main__':
    t__path_img = './TESTING_IMG'
    test_path_img = t__path_img + '/'
    ii = 55
    file_name = 'B_sample_' + str(ii) + '.png'  # 0~41
    print 'ok'
    img_shape = cv2.imread(test_path_img + file_name, 0)
    img_shape_new = img_shape
    print 'ok'
    ###########
    ###########
    print '\n'
    print '\n'
    print '=============================='

    img_shape = img_shape_new
    new_length = 64
    img_shape = cv2.resize(img_shape, (new_length, new_length), interpolation=cv2.INTER_AREA)

    print np.shape(img_shape)
    h, w = np.shape(img_shape)
    max_length = max(h, w)
    print 'h = ', h
    print 'w = ', w
    border_virgin = int(max_length / 2.2)  # max_length/3

    img = np.zeros((max_length + border_virgin, max_length + border_virgin), dtype=np.uint8)  # create blank image
    t = (max_length + border_virgin) / 16

    img_shape = img_shape * 255.0 / (1.0 * np.max(img_shape))
    #    print 'np.shape(img_shape) = ', np.shape(img_shape)

    img_shape = img_shape.astype(np.uint8)
    cv2.imshow("img_shape_1", img_shape)
	#HERE


    img_shape = cv2.cvtColor(img_shape, cv2.COLOR_GRAY2RGB)

    print np.shape(img)
    img[border_virgin / 2: border_virgin / 2 + h, border_virgin / 2: border_virgin / 2 + w] = img_shape[:, :, 0]

    print '\n'
    std_length = t * 16

    img = cv2.resize(img, (std_length, std_length), interpolation=cv2.INTER_CUBIC)

    img = img.astype(np.uint8)
    img = cv2.cvtColor(img, cv2.COLOR_GRAY2RGB)
    print 'ttt', np.shape(img)
    # print all(img[:,:,0] == img[:,:,1])
    # print any(img[:,:,0] == img[:,:,1])
    # print all(img[:,:,2] == img[:,:,1])
    # print any(img[:,:,2] == img[:,:,1])
    #
    print np.max(img[:, :, 1])
    print np.max(img[:, :, 2])

    print 'std_length = ', std_length
    cv2.imshow("000_1", img)

    h_ori, hog_image_rescaled, hog_image_hist = HoG(img, std_length)
    cv2.imshow("123_1", hog_image_hist)
    cv2.waitKey(0)

    print np.shape(hog_image_hist)
    print 'np.shape(h_ori) = ', np.shape(h_ori)
    print 'np.shape(hog_image_rescaled)=', np.shape(hog_image_rescaled)
    print 'np.shape(hog_image_hist)=', np.shape(hog_image_hist)
