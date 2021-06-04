#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from utils.net_info import NetInfo
import numpy as np
from abc import ABC, abstractmethod


class NetEvalMethod(ABC):
    @abstractmethod
    def __init__(self):
        self.eval_name = "base"

    @abstractmethod
    def eval(self, dst_audio_info : NetInfo):
        pass


class NetEvalMethodNormal(NetEvalMethod):
    def __init__(self, max_delay=400):
        super(NetEvalMethodNormal, self).__init__()
        self.eval_name = "normal"
        self.max_delay = max_delay

    def eval(self, dst_audio_info : NetInfo):
        net_data = dst_audio_info.net_data
        ssrc_info = {}

        delay_list = []
        loss_count = 0
        self.last_seqNo = {}
        for item in net_data:
            ssrc = item["packetInfo"]["header"]["ssrc"]
            sequence_number = item["packetInfo"]["header"]["sequenceNumber"]
            tmp_delay = item["packetInfo"]["arrivalTimeMs"] - item["packetInfo"]["header"]["sendTimestamp"]
            if (ssrc not in ssrc_info):
                ssrc_info[ssrc] = {
                    "time_delta" : -tmp_delay,
                    "delay_list" : [],
                    "received_nbytes" : 0,
                    "last_send_time" : item["packetInfo"]["header"]["sendTimestamp"],
                    "last_recv_time" : item["packetInfo"]["arrivalTimeMs"],
                    "recv_rate" : []
                }
            if ssrc in self.last_seqNo:
                loss_count += max(0, sequence_number - self.last_seqNo[ssrc] - 1)
            self.last_seqNo[ssrc] = sequence_number
                
            ssrc_info[ssrc]["delay_list"].append(ssrc_info[ssrc]["time_delta"] + tmp_delay)
            ssrc_info[ssrc]["received_nbytes"] += item["packetInfo"]["payloadSize"]
            tmp_send_delta = item["packetInfo"]["header"]["sendTimestamp"] - ssrc_info[ssrc]["last_send_time"]
            tmp_recv_delta = item["packetInfo"]["arrivalTimeMs"]  - ssrc_info[ssrc]["last_recv_time"]
            if not tmp_recv_delta or tmp_send_delta > tmp_recv_delta:
                ssrc_info[ssrc]["recv_rate"].append(0)
            else:
                ssrc_info[ssrc]["recv_rate"].append(tmp_send_delta / tmp_recv_delta)
            ssrc_info[ssrc]["last_send_time"] = item["packetInfo"]["header"]["sendTimestamp"]
            ssrc_info[ssrc]["last_recv_time"] = item["packetInfo"]["arrivalTimeMs"]
            
        # scale delay list
        for ssrc in ssrc_info:
            min_delay = min(ssrc_info[ssrc]["delay_list"])
            ssrc_info[ssrc]["scale_delay_list"] = [min(self.max_delay, delay) for delay in ssrc_info[ssrc]["delay_list"]]
            delay_pencentile_95 = np.percentile(ssrc_info[ssrc]["scale_delay_list"], 95)
            ssrc_info[ssrc]["delay_socre"] = (self.max_delay - delay_pencentile_95) / (self.max_delay - min_delay / 2)
        # delay score
        avg_delay_score = np.mean([ssrc_info[ssrc]["delay_socre"] for ssrc in ssrc_info])

        # receive rate score
        avg_recv_rate_score = np.mean([np.mean(ssrc_info[ssrc]["recv_rate"]) for ssrc in ssrc_info])

        # higher loss rate, lower score
        avg_loss_rate = loss_count / (loss_count + len(net_data))

        # calculate result score
        avg_score = 100 / 3
        network_score = avg_score * avg_delay_score + \
                            avg_score * avg_recv_rate_score + \
                            avg_score * (1 - avg_loss_rate)

        return network_score