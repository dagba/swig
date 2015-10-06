/* ################################################
   #                                              #
   #  PC1 CIPHER 256-bit keys ~ Alexander Pukall  #
   #  (c) NERRANT THOMAS ~ February 2003          #
   #  http://thomasnerrant.com                    #
   #                                              #
   ################################################
*/
#include <string>
#include <stdint.h>

using namespace std;

class Crypt
{
private:
    void      Prepare(const string & inKey);
    uint16_t  code();
    uint16_t  assemble();

    string    m_cle;
    string    base_table;
    uint16_t  m_x1a0[16], m_x1a2, m_ax, m_bx, m_cx, m_dx, m_si, m_cntr;

public:
//    string base_table;
//    Crypt();
    Crypt(const string & base_table);

    string Encrypt(const string & inText, const string & inKey);
    string Decrypt(const string & inText, const string & inKey);
};
