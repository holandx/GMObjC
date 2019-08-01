//
//  Sm2Utils.m
//  Created by lifei on 2019/7/9.
//  Copyright © 2019 PacteraLF. All rights reserved.
//

#import "GMSm2Utils.h"
#import "GMSm2Def.h"
#import "GMCodecUtils.h"
#import <openssl/sm2.h>
#import <openssl/evp.h>
#import <openssl/bn.h>

@implementation GMSm2Utils

///MARK: - 创建公私钥
+ (NSArray<NSString *> *)createPublicAndPrivateKey{
    NSArray<NSString *> *keyArray = @[@"", @""];
    const EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_sm2); // 椭圆曲线
    EC_KEY *key = NULL; // 密钥对
    do {
        key = EC_KEY_new();
        if (!EC_KEY_set_group(key, group)) {
            break;
        }
        if (!EC_KEY_generate_key(key)) {
            break;
        }
        const EC_POINT *pub_key = EC_KEY_get0_public_key(key);
        const BIGNUM *pri_key = EC_KEY_get0_private_key(key);

        char *hex_pub = EC_POINT_point2hex(group, pub_key, EC_KEY_get_conv_form(key), NULL);
        char *hex_pri = BN_bn2hex(pri_key);
        
        NSString *hexPubStr = [NSString stringWithCString:hex_pub encoding:NSUTF8StringEncoding];
        NSString *hexPriStr = [NSString stringWithCString:hex_pri encoding:NSUTF8StringEncoding];
        if (hexPubStr.length > 0 && hexPriStr.length > 0) {
            keyArray = @[hexPubStr, hexPriStr];
        }
        OPENSSL_free(hex_pub);
        OPENSSL_free(hex_pri);
    } while (NO);
    
    EC_KEY_free(key);
    
    return keyArray;
}

///MARK: - SM2 加密
+ (nullable NSString *)encrypt:(NSString *)plainText PublicKey:(NSString *)publicKey{
    if (!plainText || plainText.length == 0 || !publicKey || publicKey.length == 0) {
        return nil;
    }
    uint8_t *plain_text = (uint8_t *)plainText.UTF8String;
    size_t msg_len = (size_t)plainText.length;
    const char *pulic_key = publicKey.UTF8String;
    const EVP_MD *digest = EVP_sm3(); // 摘要算法
    const EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_sm2); // 椭圆曲线
    EC_KEY *key = NULL; // 密钥对
    EC_POINT *pub_point = NULL; // 坐标
    uint8_t *ctext = NULL; // 加密后 uint8_t 格式字符
    NSString *encryptedStr = nil; // 加密后的字符串对象
    do {
        key = EC_KEY_new();
        if (!EC_KEY_set_group(key, group)) {
             break;
        }
        
        pub_point = EC_POINT_new(group);
        EC_POINT_hex2point(group, pulic_key, pub_point, NULL);
        if (!EC_KEY_set_public_key(key, pub_point)) {
            break;
        }
        
        size_t ctext_len = 0;
        if (!sm2_ciphertext_size(key, digest, msg_len, &ctext_len)) {
            break;
        }
        
        ctext = (uint8_t *)OPENSSL_zalloc(ctext_len);
        if (!sm2_encrypt(key, digest, plain_text, msg_len, ctext, &ctext_len)) {
            break;
        }
        
        char *hex_ctext = OPENSSL_buf2hexstr((const uint8_t *)ctext, ctext_len);
        encryptedStr = [NSString stringWithCString:hex_ctext encoding:NSUTF8StringEncoding];
        OPENSSL_free(hex_ctext);
    } while (NO);
    
    OPENSSL_free(ctext);
    EC_POINT_free(pub_point);
    EC_KEY_free(key);
    
    return encryptedStr;
}

///MARK: - SM2 解密
+ (nullable NSString *)decrypt:(NSString *)encryptText PrivateKey:(NSString *)privateKey{
    if (!encryptText || !privateKey || encryptText.length == 0 || privateKey.length == 0) {
        return nil;
    }
    const char *private_key = privateKey.UTF8String; // 私钥
    const EVP_MD *digest = EVP_sm3(); // 摘要算法
    const EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_sm2); // 椭圆曲线
    BIGNUM *pri_big_num = NULL; // 私钥
    EC_KEY *key = NULL; // 密钥对
    EC_POINT *pub_point = NULL; // 坐标
    NSString *decryptedStr = nil; // 解密后的字符串对象
    do {
        if (!BN_hex2bn(&pri_big_num, private_key)) {
            break;
        }
        key = EC_KEY_new();
        if (!EC_KEY_set_group(key, group)) {
            break;
        }
        if (!EC_KEY_set_private_key(key, pri_big_num)) {
            break;
        }
        
        long ctext_len = 0;
        uint8_t *ctext = OPENSSL_hexstr2buf(encryptText.UTF8String, &ctext_len);
        size_t ptext_len = 0;
        if (!sm2_plaintext_size(key, digest, ctext_len, &ptext_len)) {
            break;
        }
        
        uint8_t *ptext = (uint8_t *)OPENSSL_zalloc(ptext_len);
        if (!sm2_decrypt(key, digest, ctext, ctext_len, ptext, &ptext_len)) {
            break;
        }
        
        char *sub_ptext = (char *)OPENSSL_zalloc(ptext_len + 1);
        strncpy(sub_ptext, (const char *)ptext, ptext_len);
        decryptedStr = [NSString stringWithCString:sub_ptext encoding:NSUTF8StringEncoding];
        
        OPENSSL_free(ctext);
        OPENSSL_free(ptext);
        OPENSSL_free(sub_ptext);
    } while (NO);
    
    EC_POINT_free(pub_point);
    EC_KEY_free(key);
    BN_free(pri_big_num);
    
    return decryptedStr;
}

///MARK: - ASN1 编码
+ (nullable NSString *)encodeWithASN1:(NSString *)encryptText{
    if (encryptText.length <= 192) {
        return nil;
    }
    NSString *upperEnText = encryptText.uppercaseString;
    NSString *C1xStr = [upperEnText substringWithRange:NSMakeRange(0, 64)];
    NSString *C1yStr = [upperEnText substringWithRange:NSMakeRange(64, 64)];
    NSString *C3Str = [upperEnText substringWithRange:NSMakeRange(128, 64)];
    NSString *C2Str = [upperEnText substringFromIndex:192];
    // ASN1 编码后存储数据的结构体
    struct SM2_Ciphertext_st_1 ctext_st;
    ctext_st.C2 = NULL;
    ctext_st.C3 = NULL;
    BIGNUM *x1 = NULL;
    BIGNUM *y1 = NULL;
    if (!BN_hex2bn(&x1, C1xStr.UTF8String)) {
        return nil;
    }
    if (!BN_hex2bn(&y1, C1yStr.UTF8String)) {
        return nil;
    }
    ctext_st.C1x = x1;
    ctext_st.C1y = y1;
    ctext_st.C3 = ASN1_OCTET_STRING_new();
    ctext_st.C2 = ASN1_OCTET_STRING_new();
    if (ctext_st.C3 == NULL || ctext_st.C2 == NULL) {
        return nil;
    }
    
    NSString *C3StrFormat = [GMCodecUtils addColon:C3Str];
    NSString *C2StrFormat = [GMCodecUtils addColon:C2Str];
    long C3Text_len = 0;
    uint8_t *C3Text = OPENSSL_hexstr2buf(C3StrFormat.UTF8String, &C3Text_len);
    long C2Text_len = 0;
    uint8_t *C2Text = OPENSSL_hexstr2buf(C2StrFormat.UTF8String, &C2Text_len);
    
    if (!ASN1_OCTET_STRING_set(ctext_st.C3, (uint8_t *)C3Text, (int)C3Text_len)
        || !ASN1_OCTET_STRING_set(ctext_st.C2, (uint8_t *)C2Text, (int)C2Text_len)) {
        return nil;
    }
    
    uint8_t *ctext_buf = NULL;
    int ctext_len = i2d_SM2_Ciphertext_1(&ctext_st, &ctext_buf);
    /* Ensure cast to size_t is safe */
    if (ctext_len < 0 || !ctext_buf) {
        return nil;
    }
    
    char *hex_ctext = OPENSSL_buf2hexstr((uint8_t *)ctext_buf, ctext_len);
    NSString *encodeStr = [NSString stringWithCString:hex_ctext encoding:NSUTF8StringEncoding];
    
    ASN1_OCTET_STRING_free(ctext_st.C2);
    ASN1_OCTET_STRING_free(ctext_st.C3);
    OPENSSL_free(hex_ctext);
    OPENSSL_free(ctext_buf);
    OPENSSL_free(C2Text);
    OPENSSL_free(C3Text);
    
    return encodeStr;
}

///MARK: - ASN1 解码
+ (nullable NSString *)decodeWithASN1:(NSString *)encryptText{
    if (!encryptText || encryptText.length == 0) {
        return nil;
    }
    const char *hex_ctext = encryptText.UTF8String;
    const EVP_MD *digest = EVP_sm3(); // 摘要算法
    long ctext_len = 0; // 密文原文长度
    const uint8_t *ctext = OPENSSL_hexstr2buf(hex_ctext, &ctext_len);
    
    struct SM2_Ciphertext_st_1 *sm2_st = NULL;
    sm2_st = d2i_SM2_Ciphertext_1(NULL, &ctext, ctext_len);
    // C1
    char *C1x_text = BN_bn2hex(sm2_st->C1x);
    char *C1y_text = BN_bn2hex(sm2_st->C1y);
    // C3
    const int C3_len = EVP_MD_size(digest);
    char *C3_text = OPENSSL_buf2hexstr(sm2_st->C3->data, C3_len);
    // C2
    int C2_len = sm2_st->C2->length;
    char *C2_text = OPENSSL_buf2hexstr(sm2_st->C2->data, C2_len);
    // 转 String
    NSString *C1xStr = [NSString stringWithCString:C1x_text encoding:NSUTF8StringEncoding];
    NSString *C1yStr = [NSString stringWithCString:C1y_text encoding:NSUTF8StringEncoding];
    NSString *C3Str = [[NSString stringWithCString:C3_text encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@":" withString:@""];
    NSString *C2Str = [[NSString stringWithCString:C2_text encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@":" withString:@""];
    // 拼接 C1C3C2
    NSString *decodeStr = [NSString stringWithFormat:@"%@%@%@%@", C1xStr, C1yStr, C3Str, C2Str];
    
    OPENSSL_free(C1x_text);
    OPENSSL_free(C1y_text);
    OPENSSL_free(C3_text);
    OPENSSL_free(C2_text);
    SM2_Ciphertext_1_free(sm2_st);
    return decodeStr;
}

@end
