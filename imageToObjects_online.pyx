#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function
import rospy
import numpy as np
from scipy import ndimage
from cv_bridge import CvBridge, CvBridgeError
from sensor_msgs.msg import Image
from robot_interaction_experiment.msg import Vision_Features
from robot_interaction_experiment.msg import Detected_Object
from robot_interaction_experiment.msg import Detected_Objects_List
import scipy
from sklearn.linear_model import SGDClassifier
from sklearn import svm
from myhog import hog
from skimage import exposure
import os
import cv2
import pickle
from sklearn.externals import joblib
import copy
import time
from sklearn import linear_model
from sklearn import neighbors
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import MiniBatchKMeans
from sklearn.neural_network import BernoulliRBM
from sklearn.ensemble import RandomForestClassifier
from sklearn.naive_bayes import MultinomialNB
from sklearn.naive_bayes import BernoulliNB
from sklearn.ensemble import BaggingClassifier
from joblib import Parallel, delayed
from sklearn.multiclass import OneVsRestClassifier
from multiprocessing import Process
import sklearn.svm
from multiprocessing import Pool
import random
WIDTH = 1280
LEARNN = 0
HEIGHT = 960
MAIN_WINDOW_NAME = "Segmentator"
MIN_AREA = 9000
MAX_AREA = 15000
N_COLORS = 80
TRACKBAR_NB_PROFONDEUR_NAME = "Nb img profondeur"
NB_IMG_PROFONDEUR_MAX = 100
NB_DEPTH_IMGS_INITIAL = 30
AFFICHAGE_PROFONDEUR = "Afficher img profondeur"
SHOW_DEPTH = False
AFFICHAGE_COULEUR = "Afficher img couleur"
SHOW_COLOR = False
CAPTURE_PROFONDEUR = "capture profondeur"
VAL_DEPTH_CAPTURE = 0.04
interactive = 0
DEPTH_IMG_INDEX = 0
pointsIndex = 0
NB_INDEX_BOX = 7
LAST_DEPTH_IMGS = range(NB_IMG_PROFONDEUR_MAX + 1)
NUMBER_LAST_POINTS = 15
lastpoints = np.zeros((NUMBER_LAST_POINTS, 3, 2))
lastBoxes = range(NB_INDEX_BOX + 1)
HOG_LIST = list()
last_hog = 0
indiceboxes = 0
DEPTH_IMG_AVG = 0
IMG_BGR8_CLEAN = 0
GOT_COLOR = False
GOT_DEPTH = False
CLF = SGDClassifier(loss='log')
LABELS = list()
RECORDING = 0
LABEL = ''
RECORDING_INDEX = 0
LOADED = 0
DEBUG = 0
SHOW = 0
SAVING_LEARN = 0
SAVED = 0
COLOR = ''
N_BIN = 9 #4  # number of orientations for the HoG
B_SIZE = 16 #15  # block size
C_SIZE = 8 #15  # cell size
ROTATION = -1
SAVING_TEST = 0
FAILURE = 0
TOTAL = 0
PERCENTAGE = -1
LIVE = 0
SHUFFLED_Y = list()
SHUFFLED_X = list()
LIVE_CNT = 0
def nothing(x):
    pass


def save_imgs_learn(value):
    mode = str(raw_input('Label: '))
    global LABEL
    LABEL = mode
    color_ = str(raw_input('Color: '))
    global COLOR
    COLOR = color_
    global SAVING_LEARN
    SAVING_LEARN = 1


def save_imgs_test(value):
    mode = str(raw_input('Label: '))
    global LABEL
    LABEL = mode
    color_ = str(raw_input('Color: '))
    global COLOR
    COLOR = color_
    global ROTATION
    ROTATION = str(raw_input('Rotation: '))
    global SAVING_TEST
    SAVING_TEST = 1


def changecapture(n):
    global VAL_DEPTH_CAPTURE
    if n == 0:
        n = 1
    VAL_DEPTH_CAPTURE = float(n) / 100


def changeprofondeur(n):
    global NB_DEPTH_IMGS_INITIAL
    NB_DEPTH_IMGS = n
    if NB_DEPTH_IMGS <= 0:
        NB_DEPTH_IMGS = 1


def changeaffprofondeur(b):
    global SHOW_DEPTH
    if b == 1:
        SHOW_DEPTH = True
    else:
        SHOW_DEPTH = False


def changeaffcouleur(b):
    global SHOW_COLOR
    if b == 1:
        SHOW_COLOR = True
    else:
        SHOW_COLOR = False


def clean(img, n):
    # set the non-finite values (NaN, inf) to n
    # returns 1 where the img is finite and 0 where it is not
    mask = np.isfinite(img)
    #  where mask puts img, else puts n, so where is finite puts img, else puts n
    return np.where(mask, img, n)


def callback_depth(msg):
    # treating the image containing the depth data
    global DEPTH_IMG_INDEX, LAST_DEPTH_IMGS, DEPTH_IMG_AVG, GOT_DEPTH
    # getting the image
    try:
        img = CvBridge().imgmsg_to_cv2(msg, "passthrough")
    except CvBridgeError as e:
        print (e)
        return
    cleanimage = clean(img, 255)
    if SHOW_DEPTH:
        # shows the image after processing
        cv2.imshow("Depth", img)
        cv2.waitKey(1)
    else:
        cv2.destroyWindow("Depth")
    # storing the image
    lastDepthImgs[depthImgIndex] = np.copy(cleanimage)
    depthImgIndex += 1
    if depthImgIndex > NB_DEPTH_IMGS_INITIAL:
        depthImgIndex = 0
    # creates an image which is the average of the last ones
    depth_img_Avg = np.copy(lastDepthImgs[0])
    for i in range(0, NB_DEPTH_IMGS_INITIAL):
        depth_img_Avg += lastDepthImgs[i]
    depth_img_Avg /= NB_DEPTH_IMGS_INITIAL
    got_depth = True  # ensures there is an depth image available
    if GOT_COLOR and got_depth:
        filter_by_depth()



def callback_rgb(msg):
    # processing of the color image
    global IMG_BGR8_CLEAN, GOT_COLOR
    # getting image
    try:
        img = CvBridge().imgmsg_to_cv2(msg, "bgr8")
    except CvBridgeError as e:
        print (e)
        return
    img = img[32:992, 0:1280]  # crop the image because it does not have the same aspect ratio of the depth one
    img_bgr8_clean = np.copy(img)
    got_color = True  # ensures there is an color image available
    if SHOW_COLOR:
        # show image obtained
        cv2.imshow("couleur", img_bgr8_clean)
        cv2.waitKey(1)
    else:
        cv2.destroyWindow("couleur")


def filter_by_depth():
    # Uses the depth image to only take the part of the image corresponding to the closest point and a bit further
    global DEPTH_IMG_AVG
    closest_pnt = np.amin(depth_img_Avg)
    # print np.shape(depth_img_Avg)
    depth_img_Avg = cv2.resize(depth_img_Avg, (WIDTH, HEIGHT))
    # print np.shape(depth_img_Avg)
    # generate a mask with the closest points
    img_detection = np.where(depth_img_Avg < closest_pnt + VAL_DEPTH_CAPTURE, depth_img_Avg, 0)
    # put all the pixels greater than 0 to 255
    ret, mask = cv2.threshold(img_detection, 0.0, 255, cv2.THRESH_BINARY)
    mask = np.array(mask, dtype=np.uint8)  # convert to 8-bit
    im2, contours, hierarchy = cv2.findContours(mask, 1, 2, offset=(0, -6))
    biggest_cont = contours[0]
    for cnt in contours:
        if cv2.contourArea(cnt) > cv2.contourArea(biggest_cont):
            biggest_cont = cnt
    min_area_rect = cv2.minAreaRect(biggest_cont)  # minimum area rectangle that encloses the contour cnt
    (center, size, angle) = cv2.minAreaRect(biggest_cont)
    points = cv2.boxPoints(min_area_rect)  # Find four vertices of rectangle from above rect
    points = np.int32(np.around(points))  # Round the values and make it integers
    img_bgr8_clean_copy = IMG_BGR8_CLEAN.copy()
    cv2.drawContours(img_bgr8_clean_copy, [points], 0, (0, 0, 255), 2)
    cv2.drawContours(img_bgr8_clean_copy, biggest_cont, -1, (255, 0, 255), 2)
    cv2.imshow('RBG', img_bgr8_clean_copy)
    cv2.waitKey(1)
    # if we rotate more than 90 degrees, the width becomes height and vice-versa
    if angle < -45.0:
        angle += 90.0
        width, height = size[0], size[1]
        size = (height, width)
    rot_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
    # rotate the entire image around the center of the parking cell by the
    # angle of the rotated rect
    imgwidth, imgheight = (IMG_BGR8_CLEAN.shape[0], IMG_BGR8_CLEAN.shape[1])
    rotated = cv2.warpAffine(IMG_BGR8_CLEAN, rot_matrix, (imgheight, imgwidth), flags=cv2.INTER_CUBIC)
    # extract the rect after rotation has been done
    sizeint = (np.int32(size[0]), np.int32(size[1]))
    uprightrect = cv2.getRectSubPix(rotated, sizeint, center)
    uprightrect_copy = uprightrect.copy()
    cv2.drawContours(uprightrect_copy, [points], 0, (0, 0, 255), 2)
    cv2.imshow('uprightRect', uprightrect_copy)
    objects_detector(uprightrect)


def hog_pred(value):
    global N_BIN
    global B_SIZE
    global C_SIZE
    global img_clean_GRAY_class
    fd = hog(img_clean_GRAY_class, orientations=n_bin, pixels_per_cell=(c_size, c_size),
             cells_per_block=(b_size / c_size, b_size / c_size), visualise=False)
    global CLF
    print (clf.predict([fd]))


def load_class(value):
    global CLF
    global HOG_LIST
    global LABELS
    with open('HOG_N_LABELS/HOG_N_LABELS.pickle') as f:
        hog_tuple = pickle.load(f)
    HOG_LIST = hog_tuple[0]
    labels = hog_tuple[1]
    # print (clf)
    global LOADED
    LOADED = 1
    print ('Loaded')


def show(value):
    global SHOW
    SHOW = value


def debug(value):
    global DEBUG
    DEBUG = value


def learn_callback(value):
    global LEARNN
    LEARNN = 1


def learn(value):
    print ('Learning')
    start_time = time.time()
    global HOG_LIST
    classes = np.unique(LABELS).tolist()
    for i in range(10):
        classes.append('new' + str(i))
    print (classes)
    global SHUFFLED_X
    global SHUFFLED_Y
    shuffledrange = range(len(LABELS))
    for i in range(5):
        random.shuffle(shuffledrange)
        shuffledX = [HOG_LIST[i] for i in shuffledrange]
        shuffledY = [LABELS[i] for i in shuffledrange]
        CLF.partial_fit(shuffledX, shuffledY, classes)
    print ('Done Learning')
    print('Elapsed Time Learning = ' + str(time.time() - start_time) + '\n')


def save_hog(value):
    global CLF
    HOG_TUPLE = (HOG_LIST, LABELS)
    # print ('Hog = ' + str(HOG_TUPLE[0]))
    print ('labels = ' + str(np.unique(HOG_TUPLE[1])))
    # clf.fit(HOG_TUPLE[0], HOG_TUPLE[1])
    with open('HOG_N_LABELS/HOG_N_LABELS.pickle', 'w') as f:
        pickle.dump(HOG_TUPLE, f)
    # joblib.dump(clf, 'Classifier/filename.pkl')
    print ('Done')


def hog_appender(value):
    global RECORDING
    global last_hog
    global HOG_LIST
    global CLF
    global LABELS
    print ('Already have these labels:')
    myset = set(labels)
    print (str(myset))
    mode = str(raw_input('Label: '))
    global LABEL
    LABEL = mode
    RECORDING = 1

def hog_info(value):
    global LABELS
    global HOG_LIST
    print ('Current labels = ')
    myset = set(labels)
    print (str(myset))
    print ('Current HoG size:')
    print (len(HOG_LIST))


def hog_bench(value):
    global img_clean_GRAY_class
    img_clean_GRAY_class = cv2.resize(img_clean_GRAY_class, (120, 120), interpolation=cv2.INTER_AREA)  # resize image
    timeinit = time.time()
    for i in range(500):
        fd = hog(img_clean_GRAY_class, orientations=N_BIN, pixels_per_cell=(C_SIZE, C_SIZE),
                 cells_per_block=(B_SIZE / C_SIZE, B_SIZE / C_SIZE), visualise=False)
    print (time.time()-timeinit)
    print (len(fd))


def objects_detector(img_bgr8):
    width, height, d = np.shape(img_bgr8)
    if width > 130 or height > 130:
        return
    if width < 100 or height < 100:
        return
    detected_objects_list = []
    w, l, d = np.shape(img_bgr8)
    global img_clean_BGR_learn
    img_clean_BGR_learn = img_bgr8[2:w-2, 2:l-2].copy()
    cv2.imshow('Learn', img_clean_BGR_learn)
    img_bgr8 = img_bgr8[7:w-4, 9:l-8]
    img_clean_BGR_class = img_bgr8.copy()
    img_clean_BGR_class = cv2.resize(img_clean_BGR_class, (120, 120), interpolation=cv2.INTER_AREA)  # resize image
    global img_clean_GRAY_class
    img_clean_GRAY_class = cv2.cvtColor(img_clean_BGR_class, cv2.COLOR_BGR2GRAY)
    cv2.imshow('Clean', img_clean_BGR_class)
    global CLF
    global last_hog
    global N_BIN
    global B_SIZE
    global C_SIZE
    global SAVING_LEARN
    global RECORDING
    if RECORDING == 1:
        global RECORDING_INDEX
        learn_hog(img_clean_BGR_learn)
        # HOG_LIST.append(last_hog)
        # labels.append(LABEL)
        INTERACTIONS += 1
        print (INTERACTIONS)
        if INTERACTIONS == 20:
            RECORDING = 0
            INTERACTIONS = 0
            print ('Done recording')
    global SAVED
    global SAVING_LEARN
    if SAVING_LEARN == 1:
        cv2.imwrite('LRN_IMGS/' + LABEL + '_' + str(SAVED) + '_' + COLOR + '.png', img_clean_BGR_learn)
        SAVED += 1
        print (SAVED)
        if SAVED == 3:
            SAVING_LEARN = 0
            SAVED = 0
            print ('Done saving')
    global SAVING_TEST
    cv2.imshow('Save_test', img_clean_BGR_class)
    if SAVING_TEST == 1:
        cv2.imwrite('TST_IMGS/' + LABEL + '_' + str(ROTATION) + '_' +
                    str(SAVED) + '_' + COLOR + '.png', img_clean_BGR_class)
        SAVED += 1
        print (SAVED)
        if SAVED == 20:
            SAVING_TEST = 0
            SAVED = 0
            print ('Done saving')
    best_rot = 0
    best_perc = 0
    global LIVE
    global LIVE_CNT
    global NB_DEPTH_IMGS_INITIAL
    global SHUFFLED_X
    global SHUFFLED_Y
    global HOG_LIST
    global LABELS
    if LIVE == 1:
        start_time2 = time.time()
        if LIVE_CNT == 0:
            LIVE_CNT = 100
            NB_DEPTH_IMGS = 1
            HOG_LIST = list()
            labels = list()
            HOG_LIST.extend(shuffledX[1:int(len(shuffledX)*(1.0/len((np.unique(shuffledY)))))])
            labels.extend(shuffledY[1:int(len(shuffledX)*(1.0/len(np.unique(shuffledY))))])
        learn_hog(img_bgr8)
        shuffledRange = range(len(labels))
        for i in range(5):
            random.shuffle(shuffledRange)
            shuffledX_temp = [HOG_LIST[i] for i in shuffledRange]
            shuffledY_temp = [labels[i] for i in shuffledRange]
        print (LIVE_CNT)
        LIVE_CNT -= 1
        if LIVE_CNT == 0:
            start_time = time.time()
            clf.partial_fit(shuffledX_temp, shuffledY_temp)
            print('Elapsed Time LEARNING = ' + str(time.time() - start_time) + '\n')
            LIVE = 0
            NB_DEPTH_IMGS = 30
        print('Elapsed Time TOTAL = ' + str(time.time() - start_time2) + '\n')

    global SHOW
    if SHOW == 0:
        return

    # fd, hog_image = hog(img_clean_GRAY_class, orientations=n_bin, pixels_per_cell=(c_size, c_size),
    #                         cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)
    # fd = np.reshape(fd, (32, 8))
    # fd_new = np.roll(fd, 2, axis=1)
    # fd_new = np.reshape(fd, (1, 32*8))[0]
    # print ('New')
    # print(fd_new[0:20])
    # print (len(fd_new))
    # rows, cols = img_clean_GRAY_class.shape
    # M = cv2.getRotationMatrix2D((cols / 2, rows / 2), 90, 1)
    # img_clean_BGR_class = cv2.warpAffine(img_clean_BGR_class, M, (cols, rows))
    # fd, hog_image = hog(img_clean_GRAY_class, orientations=n_bin, pixels_per_cell=(c_size, c_size),
    #                     cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)
    # print ('Rotated Original')
    # print (fd[0:20])
    # print (len(fd))
    global DEBUG
    fd2, hog_image = hog(img_clean_GRAY_class, orientations=n_bin, pixels_per_cell=(c_size, c_size),
                        cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)
    for i in range(4):
        fd2_ori = fd2.copy()
        fd2 = fd2.reshape(1, -1)
        fd, hog_image = hog(img_clean_GRAY_class, orientations=n_bin, pixels_per_cell=(c_size, c_size),
                            cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)
        fd_ori = fd.copy()
        fd = fd.reshape(1, -1)
        for percentage in clf.predict_proba(fd)[0]:
            if percentage > best_perc:
                best_perc = percentage
                best_rot = i
        fd = fd_ori
        fd2 = fd2_ori
        rows, cols = img_clean_GRAY_class.shape
        M = cv2.getRotationMatrix2D((cols / 2, rows / 2), 90, 1)
        img_clean_GRAY_class = cv2.warpAffine(img_clean_GRAY_class, M, (cols, rows))
        fd2 = np.reshape(fd2, (32, 8))
        if not i == 0:
            fd2 = np.roll(fd2, 2, axis=1)
        fd2 = np.reshape(fd2, (1, 32*8))[0]
        # print ('Original')
        # print (fd[0:20])
        # print ('Fake')
        # print (fd2[0:20])
    if DEBUG == 1:
        # print clf.predict(fd)
        print (best_perc)
        print ('\n')
    # print (best_rot)
    if not best_rot == 0:
        rows, cols, d = img_clean_BGR_class.shape
        M = cv2.getRotationMatrix2D((cols / 2, rows / 2), best_rot*90, 1)
        img_clean_BGR_class = cv2.warpAffine(img_clean_BGR_class, M, (cols, rows))
    cv2.imshow('Sent', cv2.resize(img_clean_BGR_class, (256, 256)))

    #     detected_object = Detected_Object()
    #     detected_object.id = count
    #     detected_object.image = CvBridge().cv2_to_imgmsg(img_bgr8_resized, encoding="passthrough")
    #     detected_object.center_x = unrot_center_x / float(resolution_x)  # proportion de la largeur
    #     detected_object.center_y = unrot_center_y / float(resolution_x)  # proportion de la largeur aussi
    #     detected_object.features = getpixelfeatures(object_img_rgb)
    #     detected_object.features.hog_histogram = GetHOGFeatures(object_img_rgb)
    #     detected_objects_list.append(detected_object)
    # if interactive == 1:
    #     if len(detected_objects_list) > 1:
    #         VAL_DEPTH_CAPTURE -= 0.01
    #     if len(detected_objects_list) < 1:
    #         VAL_DEPTH_CAPTURE += 0.01
    # detected_objects_list_msg = Detected_Objects_List()
    # detected_objects_list_msg.detected_objects_list = detected_objects_list
    # detected_objects_list_publisher.publish(detected_objects_list_msg)

    # cv2.rectangle(img_copy, (margin, margin), (resolution_x - margin, resolution_y - margin), (255, 255, 255))
    # cv2.imshow('detected_object', img_copy)
    # try:
    #     img_bgr8_resized
    # except NameError:
    #     pass
    # else:
    #     if 1:
    #         cv2.imshow('a', img_bgr8_resized)
    #         cv2.imshow('ROTATED', rotated_img_obj)
    #         cv2.imshow('With Cnt', object_img_rgb2)
    #     cv2.waitKey(1)

def get_img_rot(img_bgr):
    img_clean_GRAY_class_local = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    best_rot = 0
    best_perc = 0
    # pool = Pool(4)
    # hogg = pool.map(my_hog, [(0, img_clean_GRAY_class_local), (1, img_clean_GRAY_class_local),
    #                          (2, img_clean_GRAY_class_local), (3, img_clean_GRAY_class_local)])
    # perc = list()
    # for hoggg in hogg:
    #     hoggg = hoggg.reshape(1, -1)
    #     perc.append(max(clf.predict_proba(hoggg)[0]))
    # return perc.index(max(perc))
    for i in range(4):
        ########## Calculate HoG
        fd, hog_image = hog(img_clean_GRAY_class_local, orientations=N_BIN, pixels_per_cell=(C_SIZE, C_SIZE),
                            cells_per_block=(B_SIZE / C_SIZE, B_SIZE / C_SIZE), visualise=True)
        fd = fd.reshape(1, -1)
        for percentage in CLF.predict_proba(fd)[0]:
            if percentage > best_perc:
                best_perc = percentage
                best_rot = i
        rows, cols = img_clean_GRAY_class_local.shape
        M = cv2.getRotationMatrix2D((cols / 2, rows / 2), 90, 1)
        img_clean_GRAY_class_local = cv2.warpAffine(img_clean_GRAY_class_local, M, (cols, rows))
    return best_rot

def my_hog(tuple):
    index = tuple[0]
    img = tuple[1]
    rows, cols = img.shape
    if not index == 0:
        M = cv2.getRotationMatrix2D((cols / 2, rows / 2), index*90, 1)
        img = cv2.warpAffine(img, M, (cols, rows))
    fd = hog(img, orientations=N_BIN, pixels_per_cell=(C_SIZE, C_SIZE),
             cells_per_block=(B_SIZE / C_SIZE, B_SIZE / C_SIZE), visualise=False)
    return fd



def learn_hog(img):
    start_time = time.time()
    img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    global N_BIN
    global B_SIZE
    global C_SIZE
    global HOG_LIST
    global LABELS
    w, l = np.shape(img)
    img_list = list()
    img_list.append((img[:, :]))  # no changes
    global LIVE
    if LIVE == 0:
        for i in range(1, 12, 2):
            img_list.append((img[0:w-i, :]))  # cut right
            img_list.append((img[i:, :]))  # cut left
            img_list.append((img[:, i:]))  # cut up
            img_list.append((img[:, 0:l-i]))  # cut down
            img_list.append((img[:, i:l-i]))  # cut up and down
            img_list.append((img[i:w-i, :]))  # cut left and right
            img_list.append((img[i:, i:l-i]))  # cut up and down and left
            img_list.append((img[:w-i, i:l-i]))  # cut up and down and right
            img_list.append((img[i:w-i, i:l-i]))  # cut up and down and left and right
    else:
        for i in range(3, 12, 3):
            img_list.append((img[0:w-i, :]))  # cut right
            img_list.append((img[i:, :]))  # cut left
            img_list.append((img[:, i:]))  # cut up
            img_list.append((img[:, 0:l-i]))  # cut down
            img_list.append((img[:, i:l-i]))  # cut up and down
            img_list.append((img[i:w-i, :]))  # cut left and right
            img_list.append((img[i:, i:l-i]))  # cut up and down and left
            img_list.append((img[:w-i, i:l-i]))  # cut up and down and right
            img_list.append((img[i:w-i, i:l-i]))  # cut up and down and left and right
    # hog = cv2.HOGDescriptor()
    index = 0
    global SHOW
    print('Elapsed Time Pre HoG = ' + str(time.time() - start_time) + '\n')
    start_time = time.time()
    for imgs in img_list:
        imgs = cv2.resize(imgs, (120, 120), interpolation=cv2.INTER_AREA)  # resize image
        if SHOW == 1:
            cv2.imshow('img' + str(index), imgs)
        index += 1
        HOG_LIST.append(hog(imgs, orientations=n_bin, pixels_per_cell=(c_size, c_size),
                            cells_per_block=(b_size / c_size, b_size / c_size), visualise=False))
        if not LIVE == 1:
            labels.append(LABEL)
        else:
            labels.append('new0')
    print('Elapsed Time on HoG = ' + str(time.time() - start_time) + '\n')


def test_from_disk(value):
    print ('Testing from disk')
    start_time = time.time()
    path = 'TST_IMGS/'
    global LABEL
    global ROTATION
    global TOTAL
    global PERCENTAGE
    total = 0
    global FAILURE
    failure = 0
    for filename in os.listdir(path):
        total += 1
        LABEL = filename.rsplit('_', 3)[0]
        ROTATION = int(filename.rsplit('_', 3)[1])
        # print ('Label ' + str(LABEL))
        # print 'Rotation ' + str(ROTATION)
        imagee = cv2.imread(path + filename)
        imagee = cv2.resize(imagee, (120,120))
        found_rot = get_img_rot(imagee)
        if not abs(ROTATION - found_rot) < 0.5:
            # print ('Testing ' + str(filename))
            failure += 1
            # print ('Does not work')
            # cv2.imshow('Did not work',imagee)
            # cv2.waitKey(100)
            # print (found_rot)
            # print (ROTATION)
    percentage = 100 * failure / total
    print ('Failure = ' + str(percentage) + '%')
    print ('Failures = ' + str(failure))
    print('Elapsed Time Testing = ' + str(time.time() - start_time) + '\n')
    print ('Done')

def live_learn(value):
    global LIVE
    print (CLF)
    LIVE = 1

    # HOG_LIST = list()
    # labels = list()
    # learn_hog(img_clean_BGR_learn)
    # learn_hog(img_clean_BGR_learn)
    #
    # labels.append('notebook')
    # labels.append('notebook')




def learn_from_disk(value):
    path = 'LRN_IMGS/'
    global LABEL
    for filename in os.listdir(path):
        # print 'Learning ' + str(filename)
        LABEL = filename.rsplit('_', 2)[0]
        # print 'Label = ' + str(LABEL)
        imagee = cv2.imread(path + filename)
        learn_hog(imagee)
    learn(1)
    print ('Done')


def big_test(value):
    global N_BIN
    global B_SIZE
    global C_SIZE
    for bin_ in range(2, 15, 1):
        for b in range(30, 4, -1):
            start_time = time.time()
            global LABELS
            global HOG_LIST
            labels = list()
            HOG_LIST = list()
            n_bin = bin_
            b_size = b
            c_size = b
            path = 'LRN_IMGS/'
            global LABEL
            global FAILURE
            global TOTAL
            global PERCENTAGE
            print ('Creating HoG')
            for filename in os.listdir(path):
                # print 'Learning ' + str(filename)
                LABEL = filename.rsplit('_', 2)[0]
                # print 'Label = ' + str(LABEL)
                imagee = cv2.imread(path + filename)
                learn_hog(imagee)
            print ('Learning HoG')
            learn(1)
            print ('Testing HoG')
            test_from_disk(1)
            print ('Done, writting to file')
            with open('somefile.txt', 'a') as the_file:
                the_file.write('n_bin = ' + str(n_bin) + '\n')
                the_file.write('b_size = ' + str(b_size) + '\n')
                the_file.write('c_size = ' + str(c_size) + '\n')
                the_file.write('Failure = ' + str(failure) + '\n')
                the_file.write('Total = ' + str(total) + '\n')
                the_file.write('Percentage = ' + str(percentage) + '\n')
                the_file.write('Elapsed Time = ' + str(time.time() - start_time) + '\n\n\n')
            print('Written')
            print ('Elapsed Time = ' + str(time.time() - start_time) + '\n')
    print ('Big Test Done')


def GetHOGFeatures(object_img_rgb):
    std_length = 80
    global N_BIN
    global B_SIZE
    global C_SIZE
    h, w, z = np.shape(object_img_rgb)
    img = cv2.resize(object_img_rgb, (std_length, std_length), interpolation=cv2.INTER_AREA)
    img = img[:, :, 1]
    fd, hog_image = hog(img, orientations=n_bin, pixels_per_cell=(c_size, c_size),
                        cells_per_block=(b_size / c_size, b_size / c_size), visualise=True)
    hog_image = exposure.rescale_intensity(hog_image, in_range=(0, 4))
    cv2.imshow("IMAGE OF HIST", hog_image)
    return fd


def getpixelfeatures(object_img_bgr8):
    object_img_hsv = cv2.cvtColor(object_img_bgr8, cv2.COLOR_BGR2HSV)
    # gets the color histogram divided in N_COLORS "categories" with range 0-179
    colors_histo, histo_bins = np.histogram(object_img_hsv[:, :, 0], bins=N_COLORS, range=(0, 179))
    colors_histo[0] -= len(np.where(object_img_hsv[:, :, 1] == 0)[0])
    half_segment = N_COLORS / 4
    middle = colors_histo * np.array([0.0] * half_segment + [1.0] * 2 * half_segment + [0.0] * half_segment)
    sigma = 2.0
    middle = ndimage.filters.gaussian_filter1d(middle, sigma)
    exterior = colors_histo * np.array([1.0] * half_segment + [0.0] * 2 * half_segment + [1.0] * half_segment)
    exterior = np.append(exterior[2 * half_segment:], exterior[0:2 * half_segment])
    exterior = ndimage.filters.gaussian_filter1d(exterior, sigma)
    colors_histo = middle + np.append(exterior[2 * half_segment:], exterior[0:2 * half_segment])
    colors_histo = colors_histo / float(np.sum(colors_histo))
    object_shape = cv2.cvtColor(object_img_bgr8, cv2.COLOR_BGR2GRAY)
    object_shape = np.ndarray.flatten(object_shape)
    sum = float(np.sum(object_shape))
    if sum != 0:
        object_shape = object_shape / float(np.sum(object_shape))
    features = Vision_Features()
    features.colors_histogram = colors_histo
    features.shape_histogram = object_shape
    return features

def mainn():
    rospy.init_node('imageToObjects', anonymous=True)
    print ("Creating windows")
    cv2.namedWindow(MAIN_WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.createTrackbar(TRACKBAR_NB_PROFONDEUR_NAME, MAIN_WINDOW_NAME, NB_DEPTH_IMGS_INITIAL, NB_IMG_PROFONDEUR_MAX,
                       changeprofondeur)
    cv2.createTrackbar('Show', MAIN_WINDOW_NAME, 0, 1, show)
    cv2.createTrackbar(AFFICHAGE_COULEUR, MAIN_WINDOW_NAME, 0, 1, changeaffcouleur)
    cv2.createTrackbar('Learn from DISK', MAIN_WINDOW_NAME, 0, 1, learn_from_disk)
    cv2.createTrackbar('Test from DISK', MAIN_WINDOW_NAME, 0, 1, test_from_disk)
    cv2.createTrackbar('Record HoG', MAIN_WINDOW_NAME, 0, 1, hog_appender)
    cv2.createTrackbar('Save IMGs Learn', MAIN_WINDOW_NAME, 0, 1, save_imgs_learn)
    cv2.createTrackbar('Save IMGs Test', MAIN_WINDOW_NAME, 0, 1, save_imgs_test)
    cv2.createTrackbar('Info HoG', MAIN_WINDOW_NAME, 0, 1, hog_info)
    cv2.createTrackbar('Save HoG to Disk', MAIN_WINDOW_NAME, 0, 1, save_hog)
    cv2.createTrackbar('HoG Bench', MAIN_WINDOW_NAME, 0, 1, hog_bench)
    cv2.createTrackbar('Learn', MAIN_WINDOW_NAME, 0, 1, learn)
    cv2.createTrackbar('Load Class', MAIN_WINDOW_NAME, 0, 1, load_class)
    cv2.createTrackbar('Live Learn', MAIN_WINDOW_NAME, 0, 1, live_learn)
    cv2.createTrackbar('Debug', MAIN_WINDOW_NAME, 0, 1, debug)
    cv2.createTrackbar('Predict HoG', MAIN_WINDOW_NAME, 0, 1, hog_pred)
    cv2.createTrackbar(AFFICHAGE_PROFONDEUR, MAIN_WINDOW_NAME, 0, 1, changeaffprofondeur)
    cv2.createTrackbar(CAPTURE_PROFONDEUR, MAIN_WINDOW_NAME, int(100 * VAL_DEPTH_CAPTURE), 150, changecapture)
    cv2.imshow(MAIN_WINDOW_NAME, 0)
    print ("Creating subscribers")
    image_sub_rgb = rospy.Subscriber("/camera/rgb/image_rect_color", Image, callback_rgb, queue_size=1)
    image_sub_depth = rospy.Subscriber("/camera/depth_registered/image_raw/", Image, callback_depth, queue_size=1)
    detected_objects_list_publisher = rospy.Publisher('detected_objects_list', Detected_Objects_List, queue_size=1)
    print ("Spinning ROS")
    try:
        while not rospy.core.is_shutdown():
            rospy.rostime.wallsleep(0.5)
    except KeyboardInterrupt:
        print ("Shutting down")
        exit(1)
        cv2.destroyAllWindows()

# if __name__ == '__main__':
#     rospy.init_node('imageToObjects', anonymous=True)
#     print ("Creating windows")
#     cv2.namedWindow(MAIN_WINDOW_NAME, cv2.WINDOW_NORMAL)
#     cv2.createTrackbar(TRACKBAR_NB_PROFONDEUR_NAME, MAIN_WINDOW_NAME, NB_DEPTH_IMGS, NB_IMG_PROFONDEUR_MAX,
#                        changeprofondeur)
#     cv2.createTrackbar('Show', MAIN_WINDOW_NAME, 0, 1, show)
#     cv2.createTrackbar(AFFICHAGE_COULEUR, MAIN_WINDOW_NAME, 0, 1, changeaffcouleur)
#     cv2.createTrackbar('Learn from DISK', MAIN_WINDOW_NAME, 0, 1, learn_from_disk)
#     cv2.createTrackbar('Test from DISK', MAIN_WINDOW_NAME, 0, 1, test_from_disk)
#     cv2.createTrackbar('Record HoG', MAIN_WINDOW_NAME, 0, 1, hog_appender)
#     cv2.createTrackbar('Save IMGs Learn', MAIN_WINDOW_NAME, 0, 1, save_imgs_learn)
#     cv2.createTrackbar('Save IMGs Test', MAIN_WINDOW_NAME, 0, 1, save_imgs_test)
#     cv2.createTrackbar('Info HoG', MAIN_WINDOW_NAME, 0, 1, hog_info)
#     cv2.createTrackbar('Save HoG to Disk', MAIN_WINDOW_NAME, 0, 1, save_hog)
#     cv2.createTrackbar('HoG Bench', MAIN_WINDOW_NAME, 0, 1, hog_bench)
#     cv2.createTrackbar('Learn', MAIN_WINDOW_NAME, 0, 1, learn)
#     cv2.createTrackbar('Load Class', MAIN_WINDOW_NAME, 0, 1, load_class)
#     cv2.createTrackbar('Live Learn', MAIN_WINDOW_NAME, 0, 1, live_learn)
#     cv2.createTrackbar('Debug', MAIN_WINDOW_NAME, 0, 1, debug)
#     cv2.createTrackbar('Predict HoG', MAIN_WINDOW_NAME, 0, 1, hog_pred)
#     cv2.createTrackbar(AFFICHAGE_PROFONDEUR, MAIN_WINDOW_NAME, 0, 1, changeaffprofondeur)
#     cv2.createTrackbar(CAPTURE_PROFONDEUR, MAIN_WINDOW_NAME, int(100 * VAL_DEPTH_CAPTURE), 150, changecapture)
#     cv2.imshow(MAIN_WINDOW_NAME, 0)
#     print ("Creating subscribers")
#     image_sub_rgb = rospy.Subscriber("/camera/rgb/image_rect_color", Image, callback_rgb, queue_size=1)
#     image_sub_depth = rospy.Subscriber("/camera/depth_registered/image_raw/", Image, callback_depth, queue_size=1)
#     detected_objects_list_publisher = rospy.Publisher('detected_objects_list', Detected_Objects_List, queue_size=1)
#     print ("Spinning ROS")
#     try:
#         while not rospy.core.is_shutdown():
#             rospy.rostime.wallsleep(0.5)
#     except KeyboardInterrupt:
#         print ("Shutting down")
#         exit(1)
#         cv2.destroyAllWindows()