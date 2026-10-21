#include <xapian.h>
int main()
{
        Xapian::WritableDatabase db("test-db", Xapian::DB_CREATE_OR_OVERWRITE);
        Xapian::Document doc;
        doc.add_term("devkit");
        db.add_document(doc);
        db.commit();
        Xapian::Enquire q(db);
        q.set_query(Xapian::Query("devkit"));
        return q.get_mset(0, 10).size() != 1;
}
